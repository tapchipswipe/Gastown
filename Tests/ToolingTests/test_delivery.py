"""Exercise real receipt/release/mirror/packaging scripts in disposable repositories."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[2]

FAKE_BUNDLE = '''import json, plistlib, sys, zipfile
from pathlib import Path
sys.path.insert(0, str(Path('bin').resolve()))
from artifact import source_digest, digest, atomic_json
root=Path.cwd(); version=Path('version.txt').read_text().strip()
Path('build').mkdir(exist_ok=True)
binary=b'fixture binary '+version.encode()
info=plistlib.dumps(dict(CFBundleVersion=version,CFBundleShortVersionString=version))
archive=Path('build/Newton.zip')
with zipfile.ZipFile(archive,'w') as z:
    z.writestr('Newton.app/Contents/Info.plist',info)
    z.writestr('Newton.app/Contents/MacOS/Newton',binary)
atomic_json(Path('build/receipt.json'),dict(version=version,sourceSHA256=source_digest(root),archiveSHA256=digest(archive.read_bytes()),binarySHA256=digest(binary),sourceCommit=None))
'''


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='newton-tooling-')
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base/'repo'; self.root.mkdir()
        shutil.copytree(PROJECT/'bin', self.root/'bin', ignore=shutil.ignore_patterns('__pycache__'))
        (self.root/'Sources/Core').mkdir(parents=True)
        (self.root/'Sources/Core/Fixture.swift').write_text('// disposable fixture\n')
        (self.root/'Package.swift').write_text('// disposable fixture\n')
        (self.root/'MEMORY.md').write_text('# Fixture\n')
        (self.root/'version.txt').write_text('0.1.0\n')
        (self.root/'.gitignore').write_text('build/\n__pycache__/\n')
        (self.root/'fake_bundle.py').write_text(FAKE_BUNDLE)
        self.write_executable(self.root/'test.sh', '#!/bin/sh\nexit 0\n')
        self.write_executable(self.root/'build.sh', '#!/bin/sh\nset -e\npython3 -B fake_bundle.py\n')
        self.env = dict(os.environ, NEWTON_MIRROR=str(self.base/'mirror'), PYTHONDONTWRITEBYTECODE='1')
        self.cmd('git', 'init', '-b', 'main')
        self.cmd('git', 'config', 'user.name', 'Newton Fixture')
        self.cmd('git', 'config', 'user.email', 'fixture@example.invalid')
        self.commit('fixture')

    def write_executable(self, path, text):
        path.write_text(text); path.chmod(0o755)

    def cmd(self, *args, ok=True, env=None):
        result = subprocess.run(args, cwd=self.root, env=env or self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result.stdout

    def commit(self, message):
        self.cmd('git', 'add', '.')
        self.cmd('git', 'commit', '-m', message)

    def remote(self):
        bare = self.base/'origin.git'
        self.cmd('git', 'init', '--bare', str(bare))
        self.cmd('git', 'remote', 'add', 'origin', str(bare))
        self.cmd('git', 'push', '-u', 'origin', 'main')
        return bare

    def test_trusted_backlog_is_bound_to_artifact_digest(self):
        (self.root/'Automation').mkdir()
        backlog = self.root/'Automation/backlog.json'
        backlog.write_text('[]\n')
        self.cmd('./build.sh')
        self.cmd('python3', '-B', 'bin/artifact.py', 'verify')
        backlog.write_text('[{"id":"changed"}]\n')
        self.cmd('python3', '-B', 'bin/artifact.py', 'verify', ok=False)

    def test_receipt_rejects_changed_source_and_corrupted_archive(self):
        self.cmd('./build.sh')
        self.cmd('python3', '-B', 'bin/artifact.py', 'verify')
        source = self.root/'Sources/Core/Fixture.swift'
        original = source.read_bytes(); source.write_text('// changed\n')
        self.cmd('python3', '-B', 'bin/artifact.py', 'verify', ok=False)
        source.write_bytes(original)
        with (self.root/'build/Newton.zip').open('ab') as archive:
            archive.write(b'tampered')
        self.cmd('python3', '-B', 'bin/artifact.py', 'verify', ok=False)

    def test_mirror_is_exact_versioned_and_idempotent(self):
        self.cmd('./build.sh'); self.cmd('./bin/mirror.sh'); self.cmd('./bin/mirror.sh')
        mirror = self.base/'mirror'
        first = json.loads((mirror/'current.json').read_text())
        self.assertFalse(first['cloudUploadVerified'])
        self.cmd('git', 'rm', 'Sources/Core/Fixture.swift'); self.cmd('git', 'commit', '-m', 'remove fixture')
        self.cmd('./build.sh'); self.cmd('./bin/mirror.sh')
        second = json.loads((mirror/'current.json').read_text())
        self.assertNotEqual(first['snapshot'], second['snapshot'])
        self.assertTrue((mirror/first['snapshot']/'Sources/Core/Fixture.swift').exists())
        self.assertFalse((mirror/second['snapshot']/'Sources/Core/Fixture.swift').exists())

    def test_mirror_refuses_dirty_source_or_stale_artifact(self):
        self.cmd('./build.sh')
        (self.root/'MEMORY.md').write_text('uncommitted\n')
        self.cmd('./bin/mirror.sh', ok=False)
        self.cmd('git', 'restore', 'MEMORY.md')
        (self.root/'version.txt').write_text('0.1.1\n'); self.commit('version changed without build')
        self.cmd('./bin/mirror.sh', ok=False)
        self.assertFalse((self.base/'mirror/current.json').exists())

    def test_release_failure_restores_version_before_commit(self):
        self.remote()
        self.write_executable(self.root/'build.sh', '#!/bin/sh\nexit 17\n')
        self.commit('fixture build failure')
        before = self.cmd('git', 'rev-parse', 'HEAD').strip()
        self.cmd('./bin/ship.sh', ok=False)
        self.assertEqual((self.root/'version.txt').read_text(), '0.1.0\n')
        self.assertEqual(self.cmd('git', 'status', '--porcelain').strip(), '')
        self.assertEqual(before, self.cmd('git', 'rev-parse', 'HEAD').strip())

    def test_failed_push_resumes_without_another_bump_or_commit_and_repairs_missing_tag(self):
        bare = self.remote()
        hook = bare/'hooks/pre-receive'
        self.write_executable(hook, '#!/bin/sh\nexit 1\n')
        self.cmd('./bin/ship.sh', ok=False)
        journal = self.root/'.git/newton-release.json'
        state = json.loads(journal.read_text())
        self.assertEqual(state['phase'], 'committed')
        self.assertEqual((self.root/'version.txt').read_text(), '0.1.1\n')
        before = self.cmd('git', 'rev-parse', 'HEAD').strip()
        self.cmd('./bin/ship.sh', ok=False)
        self.cmd('git', 'tag', '-d', 'v0.1.1'); hook.unlink()
        self.cmd('./bin/ship.sh', '--resume')
        self.assertEqual(before, self.cmd('git', 'rev-parse', 'HEAD').strip())
        self.assertEqual((self.root/'version.txt').read_text(), '0.1.1\n')
        self.assertEqual(json.loads(journal.read_text())['phase'], 'mirrored')

    def test_symlinked_build_directory_is_not_silently_excluded_from_receipt(self):
        external=self.base/'external'; external.mkdir(); (external/'Outside.swift').write_text('// external')
        (self.root/'Sources/Linked').symlink_to(external, target_is_directory=True)
        self.cmd('python3', '-B', 'bin/artifact.py', 'digest', ok=False)

    def test_mirror_respects_existing_lock_without_removing_it(self):
        self.cmd('./build.sh')
        lock=self.root/'.git/newton-mirror-lock'; lock.mkdir()
        self.cmd('./bin/mirror.sh', ok=False)
        self.assertTrue(lock.exists())

    def mock_packaging_commands(self):
        shutil.copyfile(PROJECT/'build.sh', self.root/'build.sh')
        commands = self.base/'commands'; commands.mkdir()
        compiled = self.base/'compiled'; compiled.mkdir(); (compiled/'Newton').write_bytes(b'fixture executable')
        self.write_executable(commands/'swift', '''#!/bin/bash
if [[ "$1" == build ]]; then
  if [[ "$*" == *--show-bin-path* ]]; then printf '%s\n' "$FAKE_COMPILED_DIR"
  elif [[ "${NEWTON_MUTATE_SOURCE:-}" == 1 ]]; then printf '// changed during build\n' >> Sources/Core/Fixture.swift; fi
fi
''')
        self.write_executable(commands/'iconutil', '#!/bin/bash\nprintf icon > "${@: -1}"\n')
        self.write_executable(commands/'codesign', '#!/bin/sh\nif [ "${NEWTON_FAIL_SIGN:-}" = 1 ]; then exit 17; fi\n')
        self.write_executable(commands/'ditto', '''#!/usr/bin/env python3
import pathlib,sys,zipfile
source=pathlib.Path(sys.argv[-2])
with zipfile.ZipFile(sys.argv[-1],'w') as archive:
    for file in source.rglob('*'):
        if file.is_file(): archive.write(file,str(file.relative_to(source.parent)))
''')
        self.write_executable(commands/'mv', '''#!/usr/bin/env python3
import os,pathlib,sys
if os.environ.get('NEWTON_FAIL_PUBLISH')=='1' and pathlib.Path(sys.argv[1]).parent.name.startswith('.stage.') and pathlib.Path(sys.argv[1]).name=='receipt.json':
    raise SystemExit(17)
os.execv('/bin/mv',['mv',*sys.argv[1:]])
''')
        self.env.update(PATH=str(commands)+os.pathsep+self.env['PATH'], NEWTON_SDK='fixture-sdk', FAKE_COMPILED_DIR=str(compiled))
        self.commit('use real packaging orchestration')

    def test_failed_signing_preserves_previous_bundle_archive_receipt_and_releases_lock(self):
        self.mock_packaging_commands(); self.cmd('./build.sh')
        before = [(self.root/'build'/file).read_bytes() for file in ['Newton.zip', 'receipt.json', 'Newton.app/Contents/MacOS/Newton']]
        (self.base/'compiled/Newton').write_bytes(b'unverified replacement binary')
        env = dict(self.env, NEWTON_FAIL_SIGN='1')
        self.cmd('./build.sh', ok=False, env=env)
        after = [(self.root/'build'/file).read_bytes() for file in ['Newton.zip', 'receipt.json', 'Newton.app/Contents/MacOS/Newton']]
        self.assertEqual(before, after); self.assertFalse((self.root/'build/.build-lock').exists())

    def test_failed_publication_rolls_back_all_outputs(self):
        self.mock_packaging_commands(); self.cmd('./build.sh')
        before = [(self.root/'build'/file).read_bytes() for file in ['Newton.zip', 'receipt.json', 'Newton.app/Contents/MacOS/Newton']]
        self.cmd('./build.sh', ok=False, env=dict(self.env, NEWTON_FAIL_PUBLISH='1'))
        after = [(self.root/'build'/file).read_bytes() for file in ['Newton.zip', 'receipt.json', 'Newton.app/Contents/MacOS/Newton']]
        self.assertEqual(before, after); self.assertFalse((self.root/'build/.build-lock').exists())

    def test_source_mutation_during_build_is_rejected_and_competing_lock_is_respected(self):
        self.mock_packaging_commands(); self.cmd('./build.sh')
        previous = (self.root/'build/Newton.zip').read_bytes()
        self.cmd('./build.sh', ok=False, env=dict(self.env, NEWTON_MUTATE_SOURCE='1'))
        self.assertEqual(previous, (self.root/'build/Newton.zip').read_bytes())
        lock=self.root/'build/.build-lock'; lock.mkdir()
        self.cmd('./build.sh', ok=False)
        self.assertTrue(lock.exists())


if __name__ == '__main__':
    unittest.main()
