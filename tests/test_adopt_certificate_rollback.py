"""Regression: certificate-phase adoption rollback must not parse string fields as JSON."""
import json
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-selfsteal-3xui.sh'
code = SCRIPT.read_text().split("cat <<'PANEL_PY'\n", 1)[1].split("\nPANEL_PY", 1)[0]
helper = types.ModuleType('adopt_rollback_helper')
exec(compile(code, str(SCRIPT), 'exec'), helper.__dict__)


class FakeAPI:
    def __init__(self, rows):
        self.rows = [dict(r) for r in rows]
        self.updated = []
        self.restarts = 0

    def list(self):
        return [dict(r) for r in self.rows]

    def call(self, endpoint, payload=None):
        if endpoint.startswith('panel/api/inbounds/update/'):
            self.updated.append((endpoint, payload))
            rid = int(endpoint.rsplit('/', 1)[1])
            self.rows = [dict(payload) if r['id'] == rid else r for r in self.rows]
            return {}
        raise AssertionError('Unexpected API call: ' + endpoint)

    def restart(self):
        self.restarts += 1


class AdoptRollbackSafety(unittest.TestCase):
    def setUp(self):
        stream = {'security': 'reality', 'network': 'tcp',
                  'realitySettings': {'privateKey': 'secret',
                                      'shortIds': ['abc'],
                                      'serverNames': ['old.example.com'],
                                      'target': '127.0.0.1:9443',
                                      'xver': 1}}
        self.before = {
            'id': 2, 'port': 8443, 'protocol': 'vless',
            'tag': 'in-8443-tcp', 'listen': '127.0.0.1',
            'shareAddrStrategy': 'custom', 'shareAddr': 'old.example.com',
            'settings': json.dumps({'clients': [{'id': 'uuid-existing'}]}),
            'streamSettings': json.dumps(stream)}
        modified_stream = json.loads(self.before['streamSettings'])
        modified_stream['realitySettings']['serverNames'] = ['api2.example.com']
        modified_stream['tcpSettings'] = {'acceptProxyProtocol': True}
        self.after = dict(self.before,
                          streamSettings=json.dumps(modified_stream),
                          shareAddr='api2.example.com')
        self.original = {'reality_mode': 'parallel', 'inbound_id': 1}

    def test_comparison_uses_json_only_for_stream_settings(self):
        self.assertFalse(helper.parallel_inbound_fields_changed(
            self.before, dict(self.before)))
        self.assertTrue(helper.parallel_inbound_fields_changed(
            self.before, dict(self.before, listen='0.0.0.0')))
        self.assertTrue(helper.parallel_inbound_fields_changed(
            self.before, dict(self.before, shareAddr='foo.example.com')))
        self.assertFalse(helper.parallel_inbound_fields_changed(
            self.before, dict(self.before,
                              streamSettings=json.dumps(
                                  json.loads(self.before['streamSettings']), indent=2))))

    def rollback(self, stage, records):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            state = dict(self.original,
                         pending_adopt={'stage': stage, 'backup': str(path)})
            entries = {
                'state-before.json': self.original,
                'inbounds-before.json': [self.before],
                'inbounds-after.json': [self.after],
                'hosts-before.json': [],
                'nginx-before.json': {'managed.nginx': {'exists': False}},
            }
            for filename, data in entries.items():
                (path / filename).write_text(json.dumps(data))
            api = FakeAPI(records)
            saved = []
            with patch.object(helper, 'parallel_restore_files') as restore, \
                 patch.object(helper, 'parallel_nginx') as nginx:
                helper.parallel_adopt_rollback(
                    state, api, path, lambda: saved.append(dict(state)))
            return state, api, restore.call_count, nginx.call_count, saved

    def test_certbot_failure_restores_nginx_without_touching_xray(self):
        state, api, restored, reloaded, saved = self.rollback(
            'certificates', [self.before])
        self.assertEqual(api.updated, [])
        self.assertEqual(api.restarts, 0)
        self.assertEqual(restored, 1)
        self.assertEqual(reloaded, 1)
        self.assertNotIn('pending_adopt', state)
        self.assertTrue(saved)

    def test_xray_stage_restores_original_settings_without_losing_billing_clients(self):
        changed = dict(self.after, settings=json.dumps({'clients': [
            {'id': 'uuid-existing'}, {'id': 'uuid-new-billing'}]}))
        state, api, _, _, _ = self.rollback('xray', [changed])
        self.assertEqual(api.restarts, 1)
        self.assertEqual(len(api.updated), 1)
        self.assertEqual(api.rows[0]['shareAddr'], 'old.example.com')
        self.assertEqual(len(json.loads(api.rows[0]['settings'])['clients']), 2)
        self.assertNotIn('pending_adopt', state)


if __name__ == '__main__':
    unittest.main()
