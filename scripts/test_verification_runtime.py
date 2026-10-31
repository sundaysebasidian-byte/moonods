"""Every assertion-based verification entry point must fail closed under -O."""
import ast
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent
MESSAGE = 'verification requires assertions; Python optimization is unsupported'
ENTRYPOINTS = ['acceptance.py', 'verify_external.py', 'verify_consumer_outputs.py',
               'verify_reuse.py', 'verify_compatibility.py', 'prepare_reader_fixtures.py',
               'verify_reconcile.py']


class VerificationRuntimeTests(unittest.TestCase):
    def run_python(self, args, *, optimize=None):
        env = os.environ.copy()
        env.pop('PYTHONOPTIMIZE', None)
        if optimize is not None:
            env['PYTHONOPTIMIZE'] = optimize
        return subprocess.run([sys.executable, *args], env=env, cwd=SCRIPTS.parent,
                              capture_output=True, text=True, timeout=15)

    def require_refusal(self, result):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(MESSAGE, result.stderr)
        self.assertEqual(result.stdout, '')

    def test_cli_flags_and_environment_refuse_before_arguments_or_side_effects(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / 'must-not-exist'
            for name in ENTRYPOINTS:
                for flags, optimize in [(['-O'], None), (['-OO'], None),
                                        ([], '1'), ([], '2')]:
                    with self.subTest(script=name, flags=flags, environment=optimize):
                        self.require_refusal(self.run_python(
                            [*flags, str(SCRIPTS / name), '--output', str(output)],
                            optimize=optimize))
                        self.assertFalse(output.exists())

    def test_all_assertion_functions_are_guarded_even_when_called_as_imports(self):
        # Compile each exact function in isolation: no external tool or optional
        # dependency is needed, and the guard must run before any other globals.
        functions = []
        for path in SCRIPTS.glob('*.py'):
            if path.name.startswith('test_'):
                continue
            tree = ast.parse(path.read_text())
            for node in tree.body:
                if isinstance(node, ast.FunctionDef) and any(
                        isinstance(child, ast.Assert) for child in ast.walk(node)):
                    if path.name == 'verify_reconcile.py':
                        # This legacy driver deliberately refuses optimized imports
                        # at module entry; its CLI refusal is covered above.
                        continue
                    functions.append((path, node.name, len(node.args.args)))
        self.assertTrue(functions)
        for path, function, argc in functions:
            code = (
                'import ast,sys;sys.path.insert(0,' + repr(str(SCRIPTS)) + ');'
                'from verification_runtime import require_assertions;'
                'tree=ast.parse(open(' + repr(str(path)) + ').read());'
                'node=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='
                + repr(function) + ');'
                'exec(compile(ast.Module(body=[node],type_ignores=[]),"<entrypoint>","exec"));'
                + function + '(*[None]*' + str(argc) + ')'
            )
            with self.subTest(script=path.name, function=function):
                self.require_refusal(self.run_python(['-O', '-c', code]))

    def test_unoptimized_runtime_remains_usable(self):
        code = ('import sys;sys.path.insert(0,' + repr(str(SCRIPTS)) + ');'
                'from verification_runtime import require_assertions;require_assertions();print("OK")')
        result = self.run_python(['-c', code])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'OK\n')


if __name__ == '__main__':
    unittest.main()
