"""Safe parallel Reality migration regression tests (no live services)."""
import json
from pathlib import Path
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-selfsteal-3xui.sh'
source = SCRIPT.read_text().split("cat <<'PANEL_PY'\n", 1)[1].split("\nPANEL_PY", 1)[0]
helper = types.ModuleType('migration_safety_helper')
exec(compile(source, str(SCRIPT), 'exec'), helper.__dict__)


class MigrationSafetyTests(unittest.TestCase):
    def before(self):
        return {'id': 12, 'port': 443, 'listen': '',
                'protocol': 'vless', 'tag': 'existing-443',
                'shareAddr': 'api.example.com', 'shareAddrStrategy': 'custom',
                'settings': json.dumps({'clients': [{'id': 'old-user', 'email': 'old'}]}),
                'streamSettings': json.dumps({'security': 'reality',
                    'realitySettings': {'privateKey': 'unchanged', 'shortIds': ['aa'],
                    'target': 'original.example.com:8443'}})}

    def test_rollback_preserves_new_billing_clients(self):
        before = self.before()
        planned = dict(before, port=10443, listen='127.0.0.1',
                       shareAddr='api.example.com')
        current = dict(planned, settings=json.dumps({'clients': [
            {'id': 'old-user', 'email': 'old'},
            {'id': 'billing-new-uuid', 'email': 'billing'}]}),
            up=987, remark='changed-by-billing')
        restored = helper.parallel_rollback_inbound(before, current, planned)
        self.assertEqual(restored['port'], 443)
        self.assertEqual(restored['listen'], '')
        self.assertEqual(json.loads(restored['settings'])['clients'][1]['id'],
                         'billing-new-uuid')
        self.assertEqual(restored['up'], 987)
        self.assertEqual(restored['remark'], 'changed-by-billing')

    def test_rollback_refuses_external_reality_changes(self):
        before = self.before()
        planned = dict(before, port=10443)
        current = dict(planned, port=10555)
        with self.assertRaisesRegex(RuntimeError, 'изменено извне'):
            helper.parallel_rollback_inbound(before, current, planned)

    def test_rollback_does_not_revert_new_clients_even_if_before_equals_current(self):
        before = self.before()
        current = dict(before, settings=json.dumps({'clients': [
            {'id': 'old-user'}, {'id': 'new-user'}]}))
        restored = helper.parallel_rollback_inbound(before, current, before)
        self.assertEqual(json.loads(restored['settings'])['clients'][1]['id'],
                         'new-user')

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
