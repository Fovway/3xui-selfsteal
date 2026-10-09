"""Exercise command replacement and confirmations in temporary directories."""
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-selfsteal-3xui.sh'
SOURCE = SCRIPT.read_text()
MANAGEMENT = SOURCE.split('ensure_screenshot_dependencies() {', 1)[0]


class CascadeCliTests(unittest.TestCase):
    def run_management(self, code, *args, input=''):
        return subprocess.run(['bash', '-c', MANAGEMENT + '\n' + code,
                               'test', *map(str, args)], input=input,
                              capture_output=True, text=True)

    def test_confirmation_accepts_enter_y_and_rejects_no_invalid_and_eof(self):
        for answer, expected in [('\n', 0), ('Y\n', 0), ('y\n', 0),
                                 ('n\n', 1), ('APPLY\n', 1), ('', 1)]:
            with self.subTest(answer=answer):
                result = self.run_management("confirm 'Продолжить?'", input=answer)
                self.assertEqual(result.returncode, expected, result.stderr)

    def install(self, directory):
        # The prefix parses positional args before definitions; reset args first.
        code = MANAGEMENT.split('while (( $# )); do', 1)[0]
        definitions = MANAGEMENT.split('fail() {', 1)[1]
        code += 'fail() {' + definitions
        code += '\nSCRIPT_COMMAND="$1/cascade"\nLEGACY_SCRIPT_COMMAND="$1/selfsteal"\n'
        code += 'SCRIPT_BACKUP="$1/backup/previous.sh"\ninstall_script_command "$2"\n'
        return subprocess.run(['bash', '-c', code, 'test', str(directory), str(SCRIPT)],
                              capture_output=True, text=True)

    def test_install_replaces_managed_legacy_and_is_repeatable(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            legacy = directory / 'selfsteal'
            legacy.write_text('#!/bin/bash\n# Managed command: Fovway/3xui-selfsteal\n')
            for _ in range(2):
                result = self.install(directory)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(legacy.exists())
                command = directory / 'cascade'
                self.assertEqual(command.read_text(), SOURCE)
                self.assertEqual(command.stat().st_mode & 0o777, 0o755)
                version = subprocess.run([str(command), '--version'],
                                         capture_output=True, text=True, check=True)
                self.assertEqual(version.stdout, 'cascade 2026.10.09.15\n')

    def test_foreign_legacy_file_and_symlink_are_preserved(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            legacy = directory / 'selfsteal'
            legacy.write_text('foreign command\n')
            self.assertEqual(self.install(directory).returncode, 0)
            self.assertEqual(legacy.read_text(), 'foreign command\n')
            legacy.unlink()
            legacy.symlink_to(directory / 'cascade')
            self.assertEqual(self.install(directory).returncode, 0)
            self.assertTrue(legacy.is_symlink())

    def test_occupied_cascade_does_not_remove_legacy(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            (directory / 'cascade').write_text('foreign command\n')
            legacy = directory / 'selfsteal'
            legacy.write_text('# Managed command: Fovway/3xui-selfsteal\n')
            self.assertNotEqual(self.install(directory).returncode, 0)
            self.assertTrue(legacy.exists())
            self.assertEqual((directory / 'cascade').read_text(), 'foreign command\n')

    def test_removed_migration_flags_are_rejected(self):
        for flag in ('--parallel-reality', '--parallel-preflight', '--recover-parallel',
                     '--adopt-preflight', '--adopt-existing', '--recover-adopt', '--adopt-sni'):
            with self.subTest(flag=flag):
                result = subprocess.run(['bash', str(SCRIPT), flag],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 2)
                self.assertIn('Неизвестный аргумент', result.stderr)


if __name__ == '__main__':
    unittest.main()
