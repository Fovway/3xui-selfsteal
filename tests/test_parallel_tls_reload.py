"""Regression: nginx reload can expose an old TLS/SNI worker briefly."""
from pathlib import Path
import ssl
import types
import unittest
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-selfsteal-3xui.sh'
code = SCRIPT.read_text().split("cat <<'PANEL_PY'\n", 1)[1].split("\nPANEL_PY", 1)[0]
helper = types.ModuleType('tls_probe_helper')
exec(compile(code, str(SCRIPT), 'exec'), helper.__dict__)


class FakeSocket:
    def __init__(self):
        self.sent = []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def settimeout(self, _):
        pass

    def sendall(self, data):
        self.sent.append(data)


class FakeTLSSocket(FakeSocket):
    def recv(self, _):
        return b'HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n'


class FallbackTLSProbe(unittest.TestCase):
    def test_retries_old_nginx_worker_until_sni_is_ready(self):
        raw1, raw2, tls = FakeSocket(), FakeSocket(), FakeTLSSocket()
        context = Mock()
        context.wrap_socket.side_effect = [
            ssl.SSLError('unrecognized_name'), tls]
        with patch.object(helper.ssl, 'create_default_context', return_value=context), \
             patch.object(helper.socket, 'create_connection', side_effect=[raw1, raw2]) as con, \
             patch.object(helper.time, 'sleep') as delay:
            helper.parallel_probe_fallback([{'sni': 'api2.vline-secure.online'}], 9443)
        self.assertEqual(con.call_count, 2)
        self.assertEqual(delay.call_count, 1)
        self.assertTrue(raw1.sent[0].startswith(b'PROXY TCP4 '))
        self.assertEqual(context.wrap_socket.call_args.kwargs['server_hostname'],
                         'api2.vline-secure.online')

    def test_reports_specific_ssl_error_if_retries_exhausted(self):
        context = Mock()
        context.wrap_socket.side_effect = ssl.SSLError('tlsv1 unrecognized name')
        with patch.object(helper.ssl, 'create_default_context', return_value=context), \
             patch.object(helper.socket, 'create_connection', return_value=FakeSocket()), \
             patch.object(helper.time, 'monotonic', side_effect=[0, 11]), \
             patch.object(helper.time, 'sleep') as delay:
            with self.assertRaisesRegex(RuntimeError, 'tlsv1 unrecognized name'):
                helper.parallel_probe_fallback([{'sni': 'api2.vline-secure.online'}], 9443)
        delay.assert_not_called()

    def test_requires_active_included_nginx_vhost_and_certificate(self):
        name = 'api2.vline-secure.online'
        conf = '# configuration file ' + str(helper.PARALLEL_TLS) + ':\n'
        conf += ('server { listen 127.0.0.1:9443 ssl proxy_protocol; '
                 'server_name ' + name + '; '
                 'ssl_certificate /etc/letsencrypt/live/' + name + '/fullchain.pem; }\n')
        with patch.object(helper.subprocess, 'run',
                          return_value=types.SimpleNamespace(returncode=0, stdout=conf)):
            helper.parallel_assert_tls_vhosts([{'sni': name}])
            with self.assertRaisesRegex(RuntimeError, 'api3.vline-secure.online'):
                helper.parallel_assert_tls_vhosts([{'sni': 'api3.vline-secure.online'}])

    def test_rejects_nginx_config_not_included(self):
        with patch.object(helper.subprocess, 'run',
                          return_value=types.SimpleNamespace(returncode=0, stdout='nginx config')):
            with self.assertRaisesRegex(RuntimeError, 'include'):
                helper.parallel_assert_tls_vhosts([{'sni': 'api2.vline-secure.online'}])


if __name__ == '__main__':
    unittest.main()
