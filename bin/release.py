#!/usr/bin/env python3
"""Resumable Newton release; no force pushes or destructive history rewrites."""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'bin'))
from artifact import atomic_json, verify, version


def run(*args, output=False):
    if output:
        return subprocess.check_output(args, cwd=ROOT, text=True).strip()
    subprocess.run(args, cwd=ROOT, check=True)


@contextmanager
def release_lock(git_dir):
    lock = git_dir / 'newton-ship-lock'
    lock.mkdir()
    try:
        (lock/'pid').write_text(str(os.getpid()))
        yield
    finally:
        (lock/'pid').unlink(missing_ok=True)
        lock.rmdir()


def push_and_mirror(state, journal):
    commit = run('git', 'rev-parse', 'HEAD', output=True)
    if commit != state['commit'] or version(ROOT) != state['version']:
        raise ValueError('Release state differs from HEAD/version; refusing to bump or push another revision')
    if not run('git', 'tag', '--list', state['tag'], output=True):
        run('git', 'tag', '-a', state['tag'], '-m', f"Newton {state['version']}")
    if run('git', 'rev-parse', state['tag']+'^{commit}', output=True) != commit:
        raise ValueError('Release tag does not identify this source commit')
    verify(ROOT, ROOT/'build/Newton.zip', ROOT/'build/receipt.json')
    if state['phase'] == 'committed':
        run('git', 'push', '--atomic', 'origin', f"HEAD:refs/heads/{state['branch']}", f"refs/tags/{state['tag']}")
        refs = run('git', 'ls-remote', 'origin', f"refs/heads/{state['branch']}", f"refs/tags/{state['tag']}^{{}}", output=True)
        if len(refs.splitlines()) != 2 or any(line.split()[0] != commit for line in refs.splitlines()):
            raise ValueError('Remote branch/tag verification failed; resume safely after checking connectivity')
        state['phase'] = 'pushed'; atomic_json(journal, state)
    run('./bin/mirror.sh')
    state['phase'] = 'mirrored'; atomic_json(journal, state)
    print(f"Newton {state['version']} pushed and mirrored locally. Cloud upload unverified.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    git_dir = Path(run('git', 'rev-parse', '--absolute-git-dir', output=True))
    journal = git_dir / 'newton-release.json'
    with release_lock(git_dir):
        if run('git', 'status', '--porcelain', output=True):
            raise ValueError('Commit reviewed changes before releasing or resuming')
        if args.resume:
            if not journal.exists():
                raise ValueError('No release to resume')
            state = json.loads(journal.read_text())
            if state.get('phase') not in ('committed', 'pushed'):
                raise ValueError('No pending committed release; start a new release normally')
            push_and_mirror(state, journal)
            return
        if journal.exists() and json.loads(journal.read_text()).get('phase') in ('committed', 'pushed'):
            raise ValueError('A release is pending. Run ./bin/ship.sh --resume; do not bump again')
        branch = run('git', 'symbolic-ref', '--short', 'HEAD', output=True)
        old_version = version(ROOT)
        major, minor, patch = map(int, old_version.split('.'))
        new_version = f'{major}.{minor}.{patch+1}'; tag = 'v'+new_version
        existing = run('git', 'tag', '--list', tag, output=True)
        if existing:
            raise ValueError(f'{tag} already exists; inspect release state first')
        # A network/authorization failure should not leave a bumped version behind.
        run('git', 'push', '--dry-run', '--atomic', 'origin', f'HEAD:refs/heads/{branch}')
        run('./test.sh')
        old_memory = (ROOT/'MEMORY.md').read_bytes()
        old_version_bytes = (ROOT/'version.txt').read_bytes()
        (ROOT/'version.txt').write_text(new_version+'\n')
        state = dict(phase='building', branch=branch, version=new_version, tag=tag)
        atomic_json(journal, state)
        expected_memory = old_memory
        try:
            run('./build.sh')
            expected_memory = old_memory + f'\n## Release {new_version}\nTests and packaging passed. Delivery receipts are maintained in .git/newton-release.json; no upload inferred.\n'.encode()
            (ROOT/'MEMORY.md').write_bytes(expected_memory)
            run('git', 'add', 'version.txt', 'MEMORY.md')
            run('git', 'commit', '-m', f'release: Newton {new_version}')
        except Exception:
            # Restore only our own unchanged edits. Preserve concurrent user edits for review.
            if (ROOT/'version.txt').read_text() == new_version+'\n':
                (ROOT/'version.txt').write_bytes(old_version_bytes)
            if (ROOT/'MEMORY.md').read_bytes() == expected_memory:
                (ROOT/'MEMORY.md').write_bytes(old_memory)
            run('git', 'restore', '--staged', '--', 'version.txt', 'MEMORY.md')
            state['phase'] = 'precommit-failed'; atomic_json(journal, state)
            raise
        state['commit'] = run('git', 'rev-parse', 'HEAD', output=True)
        state['phase'] = 'committed'; atomic_json(journal, state)
        # Resume also repairs a failed tag creation without creating another commit/version.
        run('git', 'tag', '-a', tag, '-m', f'Newton {new_version}')
        push_and_mirror(state, journal)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'{error}\nIf a committed release is pending, retry with ./bin/ship.sh --resume.')
