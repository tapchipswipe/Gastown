import importlib.machinery
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class PromptTests(unittest.TestCase):
    def test_requirements_survive_large_optional_context(self):
        loader = importlib.machinery.SourceFileLoader('newton_prompt', str(ROOT/'bin/newton-prompt-gen'))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        module.read_context_brief = lambda: 'x' * 30000
        prompt = module.build_prompt('雪'*30000, 'x'*30000, ['x'*30000], {'x':'x'*30000})
        self.assertLessEqual(len(prompt), 14000)
        for text in ('./test.sh', 'off by default', 'Never merge, push', 'Swift 6'):
            self.assertIn(text, prompt)

    def test_exec_bypass_is_disabled_without_invoking_provider(self):
        with tempfile.TemporaryDirectory() as home:
            result = subprocess.run([str(ROOT/'bin/newton-prompt-gen'), 'fixture', '--exec'], text=True, capture_output=True, env={**os.environ, 'HOME':home, 'PATH':'/usr/bin:/bin'})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('owned manual runner', result.stderr)
