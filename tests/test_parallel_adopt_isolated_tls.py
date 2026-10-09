"""Regressions for isolated loopback TLS fallbacks on adopted Reality inbounds.

The original 9443 Nginx listener can have ssl_reject_handshake on;
adopted SNI must use independent loopback ports instead of sharing it.
"""
import copy
import json
from pathlib import Path
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "setup-selfsteal-3xui.sh"
source = SCRIPT.read_text().split("cat <<'PANEL_PY'\n", 1)[1].split("\nPANEL_PY", 1)[0]
helper = types.ModuleType('isolated_tls_helper')
exec(compile(source, str(SCRIPT), "exec"), helper.__dict__)


def row(ident, port, sni, target='127.0.0.1:9443'):
    return {
        'id': ident, 'port': port, 'protocol': 'vless', 'enable': True,
        'listen': '127.0.0.1', 'tag': 'in-%d-tcp' % port,
        'nodeId': None, 'settings': json.dumps({'clients': [
            {'id': 'client-%d' % ident, 'email': 'user-%d' % ident}]}),
        'streamSettings': json.dumps({
            'security': 'reality', 'network': 'tcp',
            'tcpSettings': {'acceptProxyProtocol': ident == 1},
            'realitySettings': {'privateKey': 'key-%d' % ident,
                                'shortIds': ['aa'],
                                'serverNames': [sni], 'target': target,
                                'xver': 1}})
    }


class API:
    def __init__(self, rows):
        self.rows = rows

    def list(self):
        return copy.deepcopy(self.rows)

    def call(self, endpoint):
        if endpoint == 'panel/api/hosts/list':
            return []
        raise AssertionError(endpoint)


class IsolatedTLSFallbacks(unittest.TestCase):
    def setUp(self):
        self.state = {'domain': 'api.vline-secure.online',
                      'inbound_id': 1, 'reality_mode': 'parallel',
                      'primary_internal_port': 10443, 'target_port': 9443,
                      'parallel_sni_by_id': {'1': 'api.vline-secure.online'},
                      'added_inbounds': []}
        self.primary = row(1, 10443, 'api.vline-secure.online')
        self.old2 = row(2, 8443, 'old.example.com')
        self.old3 = row(3, 8444, 'old.example.com')

    def test_adoption_allocates_distinct_available_tls_ports(self):
        api = API([self.primary, self.old2, self.old3])
        listeners = ''.join(
            'LISTEN 0 4096 127.0.0.1:%d 0.0.0.0:* users:(("xray",pid=10,fd=4))\n' % p
            for p in (8443, 8444))
        listeners += ('LISTEN 0 511 127.0.0.1:20000 0.0.0.0:* '
                      'users:(("nginx",pid=11,fd=5))\n')
        result = types.SimpleNamespace(stdout=listeners)
        main = [{'id': 1, 'sni': self.state['domain'], 'port': 10443,
                 'fallback_port': 9443, 'before': self.primary, 'after': self.primary}]
        with patch.object(helper, 'require_version'), \
             patch.object(helper, 'parallel_existing_rows', return_value=main), \
             patch.object(helper, 'parallel_dns_check'), \
             patch.object(helper.Path, 'is_dir', return_value=True), \
             patch.object(helper.Path, 'is_file', return_value=True), \
             patch.object(helper.subprocess, 'run', return_value=result):
            prior, adopted, _ = helper.parallel_adopt_plan(
                self.state, {'2': 'api2.vline-secure.online',
                             '3': 'api3.vline-secure.online'}, api)
            generated, _ = helper.parallel_texts(self.state, prior + adopted)

        self.assertEqual([r['fallback_port'] for r in adopted], [20001, 20002])
        for record in adopted:
            reality = json.loads(record['after']['streamSettings'])['realitySettings']
            old_reality = json.loads(record['before']['streamSettings'])['realitySettings']
            self.assertEqual(reality['target'], '127.0.0.1:%d' % record['fallback_port'])
            self.assertEqual(reality['privateKey'], old_reality['privateKey'])
            self.assertEqual(reality['shortIds'], old_reality['shortIds'])
            self.assertEqual(record['after']['settings'], record['before']['settings'])
        tls = generated[helper.PARALLEL_TLS]
        self.assertIn('listen 127.0.0.1:20001 ssl http2 proxy_protocol;', tls)
        self.assertIn('listen 127.0.0.1:20002 ssl http2 proxy_protocol;', tls)
        self.assertNotIn('listen 127.0.0.1:9443 ssl', tls)
        self.assertIn('api2.vline-secure.online 127.0.0.1:8443;',
                      generated[helper.PARALLEL_STREAM])

    def test_preserves_fallback_port_across_regeneration(self):
        self.state['added_inbounds'] = [{'id': 2, 'port': 8443,
                                         'fallback_port': 20001}]
        self.state['parallel_sni_by_id']['2'] = 'api2.vline-secure.online'
        adopted = row(2, 8443, 'api2.vline-secure.online', '127.0.0.1:20001')
        api = API([self.primary, adopted])
        with patch.object(helper, 'parallel_texts', return_value=({}, Path('/tmp'))):
            records = helper.parallel_existing_rows(self.state, api)
        self.assertEqual(records[1]['fallback_port'], 20001)
        self.assertEqual(records[1]['port'], 8443)
        broken = copy.deepcopy(adopted)
        json_settings = json.loads(broken['streamSettings'])
        json_settings['realitySettings']['target'] = '127.0.0.1:9443'
        broken['streamSettings'] = json.dumps(json_settings)
        with patch.object(helper, 'parallel_texts', return_value=({}, Path('/tmp'))):
            with self.assertRaisesRegex(RuntimeError, 'fallback'):
                helper.parallel_existing_rows(self.state, API([self.primary, broken]))

    def test_nginx_validation_requires_dedicated_listener(self):
        domain = 'api2.vline-secure.online'
        config = (
            '# configuration file ' + str(helper.PARALLEL_TLS) + ':\n'
            'server { listen 127.0.0.1:9443 ssl http2 proxy_protocol;\n'
            'server_name ' + domain + ';\n'
            'ssl_certificate /etc/letsencrypt/live/' + domain + '/fullchain.pem;\n}\n')
        completed = types.SimpleNamespace(returncode=0, stdout=config)
        with patch.object(helper.subprocess, 'run', return_value=completed):
            with self.assertRaisesRegex(RuntimeError, '20001'):
                helper.parallel_assert_tls_vhosts([
                    {'sni': domain, 'fallback_port': 20001}])


if __name__ == '__main__':
    unittest.main()
