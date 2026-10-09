"""Independent Reality regression tests. Does not touch live services."""
from pathlib import Path
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-selfsteal-3xui.sh'
source = SCRIPT.read_text().split("cat <<'PANEL_PY'\n", 1)[1].split("\nPANEL_PY", 1)[0]
helper = types.ModuleType('parallel_helper')
exec(compile(source, str(SCRIPT), 'exec'), helper.__dict__)


class ParallelTests(unittest.TestCase):
    def setUp(self):
        self.state = {'domain': 'main.example.com', 'inbound_id': 12,
                      'target_port': 9443, 'primary_internal_port': 10443,
                      'reality_mode': 'parallel', 'reality_chain': False,
                      'parallel_sni_by_id': {'12': 'main.example.com', '15': 'edge.example.com'},
                      'added_inbounds': [{'id': 15, 'port': 8443}]}

    def config(self):
        rows = [{'id': 12, 'port': 10443, 'sni': 'main.example.com'},
                {'id': 15, 'port': 8443, 'sni': 'edge.example.com'}]
        with patch.object(helper.Path, 'is_dir', return_value=True), patch.object(
                helper.Path, 'is_file', return_value=True):
            return helper.parallel_texts(self.state, rows)[0]

    def test_nginx_routes_sni_with_only_443_public(self):
        files = self.config()
        stream = files[helper.PARALLEL_STREAM]
        self.assertIn('listen 443;', stream)
        self.assertIn('listen [::]:443;', stream)
        self.assertIn('main.example.com 127.0.0.1:10443;', stream)
        self.assertIn('edge.example.com 127.0.0.1:8443;', stream)
        self.assertNotIn('listen 8443;', stream)
        self.assertIn('default 127.0.0.1:9443;', stream)
        self.assertIn('proxy_protocol on;', stream)

    def test_https_fallback_has_same_extra_sni(self):
        files = self.config()
        tls = files[helper.PARALLEL_TLS]
        self.assertIn('server_name edge.example.com;', tls)
        self.assertIn('listen 127.0.0.1:9443 ssl http2 proxy_protocol;', tls)
        self.assertNotIn('listen 443;', tls)
        self.assertIn('server_name edge.example.com;', files[helper.PARALLEL_ACME])

    def test_invalid_sni_is_not_accepted(self):
        for bad in ['', '*.example.com', 'https://foo.example.com',
                    'foo.example.com;', 'foo.example.com/bar']:
            with self.subTest(bad=bad):
                with self.assertRaises(RuntimeError):
                    helper.parallel_validate_sni(bad)
        self.assertEqual(helper.parallel_validate_sni('EDGE.Example.COM.'),
                         'edge.example.com')

    def test_host_link_stays_on_external_443(self):
        before = dict(inboundIds=[15], remark='original', hosts=['main.example.com'],
                      port=443, security='same', isHidden=True)
        after = helper.parallel_host_payload(before, 15, 'edge.example.com')
        self.assertEqual(after['hosts'], ['edge.example.com'])
        self.assertEqual(after['port'], 443)
        self.assertEqual(after['remark'], 'original')
        self.assertTrue(after['isHidden'])


    def test_existing_user_nginx_file_is_never_overwritten(self):
        with patch.object(helper.Path, 'is_symlink', return_value=False), patch.object(
                helper.Path, 'exists', return_value=True), patch.object(
                helper.Path, 'is_file', return_value=True), patch.object(
                helper.Path, 'read_text', return_value='user nginx config\n'):
            with self.assertRaisesRegex(RuntimeError, 'не принадлежит'):
                helper.parallel_backup_files({helper.PARALLEL_STREAM: ''})

    def test_legacy_repair_cannot_modify_parallel(self):
        with self.assertRaisesRegex(RuntimeError, 'параллельном'):
            helper.repair_chain(dict(self.state), lambda: None)


    def test_runtime_must_bind_loopback_not_public_ip(self):
        import json
        state = dict(self.state, panel_binary='/usr/local/x-ui/x-ui')
        settings = {'security': 'reality',
                    'tcpSettings': {'acceptProxyProtocol': True},
                    'realitySettings': {'privateKey': 'secret', 'shortIds': ['aa'],
                                        'serverNames': ['main.example.com'],
                                        'target': '127.0.0.1:9443', 'xver': 1}}
        row = dict(id=12, tag='selfsteal-reality-10443', protocol='vless',
                   port=10443, listen='127.0.0.1',
                   settings=json.dumps({'clients': []}),
                   streamSettings=json.dumps(settings))
        records = [{'id': 12, 'port': 10443, 'sni': 'main.example.com',
                    'before': row, 'after': row}]
        bad_socket = 'LISTEN 0 4096 0.0.0.0:10443 0.0.0.0:* users:(("xray-linux-amd64",pid=25,fd=7))'
        class Completed:
            stdout = bad_socket
        class FakeApi:
            def list(self):
                return [row]
        with patch.object(helper.subprocess, 'run', return_value=Completed()), \
                patch.object(helper.time, 'sleep'):
            with self.assertRaisesRegex(RuntimeError, '0.0.0.0'):
                helper.parallel_runtime(state, records, FakeApi())


    def test_inbound_duplicate_sni_never_calls_panel(self):
        state = dict(self.state, panel_binary='/usr/local/x-ui/x-ui')
        with patch.object(helper, 'require_version'), \
                patch.object(helper, 'API'), \
                patch.object(helper, 'parallel_existing_rows', return_value=[
                    {'sni': 'main.example.com'}, {'sni': 'edge.example.com'}]):
            with self.assertRaisesRegex(RuntimeError, 'уже назначен'):
                helper.parallel_add_inbound(state, 10455, 'edge.example.com', lambda: None)


if __name__ == '__main__':
    unittest.main()
