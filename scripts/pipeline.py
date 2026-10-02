"""Native CI checks, CLI archive production, and release version validation."""

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path
from typing import TypedDict, cast

SYSTEMS = ('x86_64-linux', 'aarch64-linux', 'aarch64-darwin')
SEMVER = re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z')
SHA = re.compile(r'[0-9a-f]{40}\Z')
CommandArg = str | os.PathLike[str]


class LockNode(TypedDict):
    locked: dict[str, str]


class LockData(TypedDict):
    nodes: dict[str, LockNode]


class Options(argparse.Namespace):
    command: str = ''
    system: str = ''
    pr_head_sha: str = ''
    pr_base_sha: str = ''
    base_ref: str = ''
    version_file: Path = Path()
    base_version: str = ''
    changelog_file: Path = Path()
    require_bump: bool = False
    allow_existing_tag: bool = False


def log_command(*command: CommandArg) -> None:
    print(f'+ {shlex.join(map(str, command))}', flush=True)


def run(*command: CommandArg) -> None:
    log_command(*command)
    _ = subprocess.run(command, check=True)


def output(*command: CommandArg) -> str:
    log_command(*command)
    result = subprocess.run(command, check=True, text=True, stdout=subprocess.PIPE)
    return result.stdout.strip()


def require(condition: object, message: str) -> None:
    if not condition:
        raise ValueError(message)


def build_path(attribute: str) -> Path:
    return Path(
        output(
            'nix',
            'build',
            '--no-update-lock-file',
            '--no-link',
            '--print-out-paths',
            attribute,
        )
    )


def verify_closure(package: Path, excluded: Path | None = None) -> None:
    paths = output('nix-store', '-q', '--requisites', package).splitlines()
    if excluded is not None:
        require(str(excluded) not in paths, 'prebuilt package still references the source package')
    for path in paths:
        require(Path(path).exists(), f'runtime closure path is missing: {path}')


def verify_version(
    version_file: Path | str,
    base: str,
    changelog_file: Path | str,
    require_bump: bool = False,
    allow_existing_tag: bool = False,
) -> None:
    version = Path(version_file).read_text().strip()
    require(
        SEMVER.fullmatch(version) and SEMVER.fullmatch(base),
        'VERSION and base version must be plain major.minor.patch numbers',
    )
    if version == base:
        require(not require_bump, f'release version {version} has not been bumped')
        print(f'no release version change ({version})')
        return
    require(
        tuple(map(int, version.split('.'))) > tuple(map(int, base.split('.'))),
        f'release version {version} must exceed {base}',
    )

    lines = Path(changelog_file).read_text().splitlines()
    heading = re.compile(rf'## \[{re.escape(version)}\](?:\s|$)')
    start = next((i for i, line in enumerate(lines) if heading.match(line)), None)
    if start is None:
        raise ValueError(f'CHANGELOG.md needs a section for {version}')
    notes: list[str] = []
    for line in lines[start + 1 :]:
        if line.startswith('## '):
            break
        notes.append(line)
    require(
        any(line.strip() and not line.lstrip().startswith('#') for line in notes),
        f'CHANGELOG.md section for {version} is empty',
    )
    if not allow_existing_tag:
        require(
            not output('git', 'tag', '--list', f'v{version}'),
            f'tag v{version} already exists',
        )
    print(f'release candidate v{version} is valid')


def release_candidate(base_ref: str) -> None:
    require(bool(base_ref) and ':' not in base_ref, 'invalid pull request base ref')
    base = subprocess.run(
        ('git', 'show', f'origin/{base_ref}:VERSION'),
        capture_output=True,
        text=True,
        check=False,
    )
    if base.returncode == 0:
        base_version = base.stdout.strip()
    else:
        tags = output('git', 'tag', '--list', 'v*', '--sort=-v:refname').splitlines()
        base_version = tags[0][1:] if tags else ''
    verify_version('VERSION', base_version, 'CHANGELOG.md')


def build_archive(system: str) -> None:
    # Release production always selects the pinned source package.
    run('nix', 'build', '-L', '--no-update-lock-file', '--no-link', '.#grit-source')
    run(
        'nix',
        'build',
        '-L',
        '--no-update-lock-file',
        '--no-link',
        '.#grit-artifact',
        '.#grit-local-prebuilt',
    )
    equivalence = f'.#checks.{system}.equivalence'
    run('nix', 'build', '-L', '--no-update-lock-file', '--no-link', equivalence)
    run(
        'nix',
        'build',
        '-L',
        '--no-update-lock-file',
        '--no-link',
        '--offline',
        equivalence,
    )

    source = build_path('.#grit-source')
    prebuilt = build_path('.#grit-local-prebuilt')
    archive = build_path('.#grit-artifact')
    lock = cast(LockData, json.loads(Path('flake.lock').read_text()))['nodes']
    with tarfile.open(archive, 'r:gz') as bundle:
        metadata_file = bundle.extractfile('./metadata.json')
        if metadata_file is None:
            raise ValueError('CLI archive has no metadata.json')
        metadata = cast(dict[str, object], json.load(metadata_file))
    require(
        metadata.get('format') == 1
        and metadata.get('system') == system
        and metadata.get('sourceRev') == lock['gritql-src']['locked']['rev']
        and metadata.get('nixpkgsRev') == lock['nixpkgs-pinned']['locked']['rev'],
        'CLI archive metadata does not match the pinned source and toolchain',
    )

    verify_closure(prebuilt, source)
    run(source / 'bin/grit', '--version')
    run(prebuilt / 'bin/grit', '--version')
    executable = prebuilt / 'bin/grit'
    if system.endswith('-linux'):
        program_headers = output('readelf', '-l', executable)
        dynamic = output('readelf', '-d', executable)
        require(
            'interpreter' in program_headers and 'NEEDED' in dynamic,
            'prebuilt ELF is missing its interpreter or dynamic dependencies',
        )
        print('\n'.join(line.strip() for line in program_headers.splitlines() if 'interpreter' in line))
        print('\n'.join(line.strip() for line in dynamic.splitlines() if 'NEEDED' in line or 'RUNPATH' in line))
    else:
        run('otool', '-L', executable)

    version = output(
        'nix',
        'eval',
        '--raw',
        '--no-update-lock-file',
        f'.#packages.{system}.grit-source.version',
    )
    name = f'grit-{version}-{system}.tar.gz'
    destination = Path('dist')
    destination.mkdir(exist_ok=True)
    _ = shutil.copyfile(archive, destination / name)
    with (destination / name).open('rb') as archive_file:
        digest = hashlib.file_digest(archive_file, 'sha256').hexdigest()
    _ = (destination / f'{name}.sha256').write_text(f'{digest}  {name}\n')
    print(f'wrote {destination / name} ({digest})')


def native(system: str, head_sha: str, base_sha: str) -> None:
    require(bool(head_sha) == bool(base_sha), 'both PR head and base SHAs are required')
    if head_sha:
        require(
            SHA.fullmatch(head_sha) and SHA.fullmatch(base_sha),
            'PR head and base must be 40-character commit SHAs',
        )
        require(output('git', 'rev-parse', 'HEAD^1') == base_sha, 'checked-out candidate has a different base')
        require(output('git', 'rev-parse', 'HEAD^2') == head_sha, 'checked-out candidate has a different head')

    lock = cast(LockData, json.loads(Path('flake.lock').read_text()))['nodes']
    source_rev = lock['gritql-src']['locked']['rev']
    artifact_rev = output('nix', 'eval', '--impure', '--raw', '--expr', '(import ./nix/artifacts.nix).sourceRev')
    has_matching_artifact = source_rev == artifact_rev
    require(
        has_matching_artifact or bool(head_sha),
        'pinned Grit source has no matching published artifact on main',
    )
    if has_matching_artifact:
        run('nix', 'flake', 'check', '-L', '--keep-going', '--no-update-lock-file')
    else:
        print('candidate source pin has no published CLI; checking the explicit source build', flush=True)
    run(
        'nix',
        'flake',
        'check',
        '-L',
        '--keep-going',
        '--no-update-lock-file',
        'path:.?dir=qa',
    )
    if has_matching_artifact:
        run('nix', 'build', '-L', '.#grit', '--no-update-lock-file')
        run('nix', 'build', '-L', '--offline', '.#grit', '--no-update-lock-file')
        run('nix', 'run', '.#grit', '--no-update-lock-file', '--', '--version')
        verify_closure(build_path('.#grit'))

    if head_sha:
        build_archive(system)
        tree = output('git', 'rev-parse', 'HEAD^{tree}')
        _ = Path('dist/candidate.json').write_text(
            json.dumps(
                {
                    'headSha': head_sha,
                    'baseSha': base_sha,
                    'treeSha': tree,
                },
                indent=2,
            )
            + '\n'
        )


def evaluate() -> None:
    run('nix', 'flake', 'show', '--all-systems', '--no-update-lock-file')
    run(
        'nix',
        'flake',
        'show',
        '--all-systems',
        '--no-update-lock-file',
        'path:.?dir=qa',
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    native_parser = commands.add_parser('native', help='run checks and build a PR CLI archive')
    _ = native_parser.add_argument('--system', choices=SYSTEMS, required=True)
    _ = native_parser.add_argument('--pr-head-sha', default=os.getenv('PR_HEAD_SHA', ''))
    _ = native_parser.add_argument('--pr-base-sha', default=os.getenv('PR_BASE_SHA', ''))
    candidate_parser = commands.add_parser('release-candidate', help='validate a PR release version')
    _ = candidate_parser.add_argument('--base-ref', required=True)
    _ = commands.add_parser('evaluate', help='evaluate both flakes on all supported systems')
    version_parser = commands.add_parser('check-version', help='validate a version and changelog')
    _ = version_parser.add_argument('version_file', type=Path)
    _ = version_parser.add_argument('base_version')
    _ = version_parser.add_argument('changelog_file', type=Path)
    _ = version_parser.add_argument('--require-bump', action='store_true')
    _ = version_parser.add_argument('--allow-existing-tag', action='store_true')
    args = parser.parse_args(namespace=Options())
    try:
        if args.command == 'native':
            native(args.system, args.pr_head_sha, args.pr_base_sha)
        elif args.command == 'release-candidate':
            release_candidate(args.base_ref)
        elif args.command == 'evaluate':
            evaluate()
        else:
            verify_version(
                args.version_file,
                args.base_version,
                args.changelog_file,
                args.require_bump,
                args.allow_existing_tag,
            )
    except (
        ValueError,
        OSError,
        subprocess.CalledProcessError,
        tarfile.TarError,
    ) as error:
        print(f'pipeline: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
