"""3x-ui 3.8.5 automatically renames VLESS TCP inbound tags on port changes."""
import json
from pathlib import Path
import types
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-selfsteal-3xui.sh'
source = SCRIPT.read_text().split("cat <<'PANEL_PY'\n", 1)[1].split("\nPANEL_PY", 1)[0]
helper = types.ModuleType('auto_tag_helper')
exec(compile(source, str(SCRIPT), 'exec'), helper.__dict__)


class ParallelAutoTagTests(unittest.TestCase):
    def setUp(self):
        self.before = {
            'id': 1, 'tag': 'in-443-tcp', 'port': 443, 'listen': '127.0.0.1',
            'protocol': 'vless',
            'settings': json.dumps({'clients': [
                {'id': 'original-uuid', 'email': 'existing'}]}),
            'streamSettings': json.dumps({
                'network': 'tcp', 'security': 'reality',
                'realitySettings': {
                    'privateKey': 'key', 'shortIds': ['aabbcc'],
                    'serverNames': ['api.example.com'], 'xver': 1,
                    'target': '127.0.0.1:9443'},
                'tcpSettings': {'acceptProxyProtocol': True}})}
        self.after = dict(self.before, port=10443)
        self.record = {'id': 1, 'port': 10443, 'sni': 'api.example.com',
                       'before': self.before, 'after': self.after}

    def test_generated_tag_is_renamed_to_new_port(self):
        self.assertTrue(helper.parallel_tag_matches(
            self.before, 10443, 'in-10443-tcp'))
        self.assertTrue(helper.parallel_tag_matches(
            self.before, 10443, 'in-10443-tcp-2'))
        for value in ('in-443-tcp', 'in-10444-tcp', 'unknown-tag',
                      'in-10443-udp', 'in-10443-tcp-1'):
            with self.subTest(value=value):
                self.assertFalse(helper.parallel_tag_matches(
                    self.before, 10443, value))

    def test_panel_accepts_valid_auto_rename_and_preserves_uuids(self):
        current = dict(self.after, tag='in-10443-tcp',
                       settings=json.dumps({'clients': [
                           {'id': 'original-uuid', 'email': 'existing'},
                           {'id': 'billing-added', 'email': 'new'}]}))
        helper.parallel_panel_runtime([self.record], [current])

    def test_extra_inbound_without_port_change_must_keep_tag(self):
        previous = dict(self.before, id=2, port=8443, tag='in-8443-tcp')
        rec = dict(self.record, id=2, port=8443,
                   before=previous, after=previous)
        helper.parallel_panel_runtime([rec], [previous])
        wrong = dict(previous, tag='in-8443-tcp-2')
        with self.assertRaisesRegex(RuntimeError, 'неожиданный tag'):
            helper.parallel_panel_runtime([rec], [wrong])

    def test_custom_tag_is_not_renamed(self):
        before = dict(self.before, tag='my-vless')
        self.assertTrue(helper.parallel_tag_matches(
            before, 10443, 'my-vless'))
        self.assertFalse(helper.parallel_tag_matches(
            before, 10443, 'in-10443-tcp'))


if __name__ == '__main__':
    unittest.main()
