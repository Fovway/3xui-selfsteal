"""Read-only checks for Xray hot-reload and chain-listen regression."""
import json
from pathlib import Path
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-selfsteal-3xui.sh'
source = SCRIPT.read_text().split("cat <<'PANEL_PY'\n", 1)[1].split("\nPANEL_PY", 1)[0]
helper = types.ModuleType('runtime_safety_helper')
exec(compile(source, str(SCRIPT), 'exec'), helper.__dict__)


class RuntimeSafetyTests(unittest.TestCase):
    def setUp(self):
        stream = {'network': 'tcp', 'security': 'reality',
                  'tcpSettings': {'acceptProxyProtocol': True},
                  'realitySettings': {
                      'privateKey': 'secret-key', 'shortIds': ['aabb'],
                      'serverNames': ['main.example.com'], 'xver': 1,
                      'target': '127.0.0.1:9443'}}
        self.before = dict(id=12, tag='reality-primary', protocol='vless',
                           port=443, listen='0.0.0.0',
                           settings=json.dumps({'clients': [
                               {'id': 'existing-uuid', 'email': 'user1'}]}),
                           streamSettings=json.dumps(stream))
        self.after = dict(self.before, port=10443, listen='127.0.0.1')
        self.records = [{'id': 12, 'port': 10443, 'sni': 'main.example.com',
                         'before': self.before, 'after': self.after}]
        self.ss = 'LISTEN 0 4096 127.0.0.1:10443 0.0.0.0:* users:(("xray-linux-amd64",pid=25,fd=7))'

    def test_panel_allows_additional_clients_without_discarding_old_uuid(self):
        current = dict(self.after, settings=json.dumps({'clients': [
            {'id': 'existing-uuid', 'email': 'user1'},
            {'id': 'new-billing-uuid', 'email': 'user2'}]}))
        helper.parallel_panel_runtime(self.records, [current])

    def test_panel_refuses_missing_existing_uuid(self):
        current = dict(self.after, settings=json.dumps({'clients': [
            {'id': 'new-billing-uuid', 'email': 'user2'}]}))
        with self.assertRaisesRegex(RuntimeError, 'Исчезли UUID'):
            helper.parallel_panel_runtime(self.records, [current])

    def test_panel_refuses_changed_reality_settings(self):
        broken = json.loads(self.after['streamSettings'])
        broken['realitySettings']['target'] = '203.0.113.1:8443'
        current = dict(self.after, streamSettings=json.dumps(broken))
        with self.assertRaisesRegex(RuntimeError, 'Reality/SNI/PROXY'):
            helper.parallel_panel_runtime(self.records, [current])

    def test_listener_requires_loopback_xray_and_unique_port(self):
        helper.parallel_live_listeners(self.ss, self.records)
        for wrong in (
            'LISTEN 0 4096 0.0.0.0:10443 0.0.0.0:* users:(("xray",pid=1,fd=2))',
            'LISTEN 0 4096 127.0.0.1:10443 0.0.0.0:* users:(("nginx",pid=1,fd=2))',
            '',
            self.ss + '\n' + self.ss,
        ):
            with self.subTest(line=wrong), self.assertRaises(RuntimeError):
                helper.parallel_live_listeners(wrong, self.records)

    def test_runtime_does_not_read_stale_config_file(self):
        class Api:
            def list(inner):
                return [self.after]
        class Result:
            stdout = self.ss
        with patch.object(helper.subprocess, 'run', return_value=Result()), \
                patch.object(helper, 'parallel_probe_fallback') as probe, \
                patch.object(helper.Path, 'read_text', side_effect=AssertionError('stale config.json')):
            helper.parallel_runtime({}, self.records, Api())
            probe.assert_called_once_with([self.records[0]], 10443)

    def test_chain_error_explains_inbound_and_invalid_listen(self):
        before = dict(self.before, listen='192.0.2.55')
        settings = json.loads(before['streamSettings'])
        settings['realitySettings'].update(serverNames=['main.example.com'])
        before['streamSettings'] = json.dumps(settings)
        class Api:
            def list(self):
                return [before]
        state = {'inbound_id': 12, 'domain': 'main.example.com',
                 'added_inbounds': [], 'target_port': 9443}
        with self.assertRaisesRegex(RuntimeError, 'Inbound ID 12.*listen=192.0.2.55'):
            helper.chain_plan(Api(), state)


if __name__ == '__main__':
    unittest.main()
