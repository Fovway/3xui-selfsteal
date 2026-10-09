"""Parallel Reality runtime safety regression tests (no live services)."""
from pathlib import Path
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-selfsteal-3xui.sh'
source = SCRIPT.read_text().split("cat <<'PANEL_PY'\n", 1)[1].split("\nPANEL_PY", 1)[0]
helper = types.ModuleType('runtime_safety_helper')
exec(compile(source, str(SCRIPT), 'exec'), helper.__dict__)


class RuntimeSafetyTests(unittest.TestCase):
    def test_nginx_restore_refuses_foreign_file(self):
        entry = {'/etc/nginx/test.conf': {'exists': False}}
        with patch.object(helper.Path, 'exists', return_value=True), \
             patch.object(helper.Path, 'is_symlink', return_value=False), \
             patch.object(helper.Path, 'is_file', return_value=True), \
             patch.object(helper.Path, 'read_bytes', return_value=b'custom-config\n'):
            with self.assertRaisesRegex(RuntimeError, 'изменён извне'):
                helper.parallel_restore_files(entry)

    def test_nginx_syntax_error_has_stage_reason(self):
        class Completed:
            returncode = 1
            stderr = 'nginx: [emerg] unknown directive "something" in /etc/nginx/conf.d/test.conf:1'
        with patch.object(helper.subprocess, 'run', return_value=Completed()):
            with self.assertRaisesRegex(RuntimeError, 'unknown directive'):
                helper.parallel_nginx()

    def test_preflight_fallback_fails_closed(self):
        with patch.object(helper.socket, 'create_connection', side_effect=OSError('refused')):
            with self.assertRaisesRegex(RuntimeError, 'HTTPS-заглушка'):
                helper.parallel_probe_fallback([{'sni': 'api.example.com'}], 9443)


if __name__ == '__main__':
    unittest.main()
