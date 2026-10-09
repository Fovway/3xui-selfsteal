"""Regression: ACME HTTP vhosts must reuse the primary IPv4 bind address.

Nginx's configuration test can pass even when a subsequent reload fails
with EADDRINUSE because a new wildcard :80 overlaps an existing public-IP :80.
"""
import tempfile
from pathlib import Path
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-selfsteal-3xui.sh'
source = SCRIPT.read_text().split("cat <<'PANEL_PY'\n", 1)[1].split("\nPANEL_PY", 1)[0]
helper = types.ModuleType('parallel_http_listener_helper')
exec(compile(source, str(SCRIPT), 'exec'), helper.__dict__)


class HTTPBindRegression(unittest.TestCase):
    def make_site(self, root, text):
        path = Path(root) / 'main-site.conf'
        path.write_text(text)
        return {'domain': 'api.vline-secure.online', 'nginx_site': str(path),
                'target_port': 9443}

    def test_public_ipv4_and_default_server_share_specific_address(self):
        with tempfile.TemporaryDirectory() as folder:
            state = self.make_site(folder, (
                'server { listen 144.31.15.18:80 default_server; '
                'server_name _; return 444; }\n'
                'server { listen 144.31.15.18:80; '
                'server_name api.vline-secure.online; '
                'location ^~ /.well-known/acme-challenge/ { root /var/www/test; } }\n'))
            self.assertEqual(helper.parallel_http_listens(state),
                             '    listen 144.31.15.18:80;\n')
            records = [{'id': 1, 'port': 10443, 'sni': state['domain']},
                       {'id': 2, 'port': 8443, 'sni': 'api2.vline-secure.online',
                        'fallback_port': 20000},
                       {'id': 3, 'port': 8444, 'sni': 'api3.vline-secure.online',
                        'fallback_port': 20001}]
            with patch.object(helper.Path, 'is_dir', return_value=True):
                # Generated root/index.html is present on the real server.
                with patch.object(helper.Path, 'is_file', return_value=True):
                    configs, _ = helper.parallel_texts(state, records)
            acme = configs[helper.PARALLEL_ACME]
            self.assertEqual(acme.count('listen 144.31.15.18:80;'), 2)
            self.assertNotIn('    listen 80;', acme)
            self.assertNotIn('listen [::]:80;', acme)
            self.assertIn('server_name api2.vline-secure.online;', acme)
            self.assertIn('server_name api3.vline-secure.online;', acme)

    def test_existing_wildcard_and_ipv6_retained_when_present(self):
        with tempfile.TemporaryDirectory() as folder:
            state = self.make_site(folder, (
                'server { listen 80 default_server; listen [::]:80; '
                'server_name _; return 444; }'))
            self.assertEqual(helper.parallel_http_listens(state),
                             '    listen 80;\n    listen [::]:80;\n')

    def test_no_new_ipv6_binding_when_primary_ipv4_only(self):
        with tempfile.TemporaryDirectory() as folder:
            state = self.make_site(folder, (
                'server { listen 192.0.2.100:80; server_name api.vline-secure.online; }'))
            self.assertNotIn('[::]', helper.parallel_http_listens(state))

    def test_multiple_ipv4_listeners_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            state = self.make_site(folder, (
                'server { listen 192.0.2.100:80; }\n'
                'server { listen 198.51.100.9:80; }'))
            with self.assertRaisesRegex(RuntimeError, 'несколько IPv4'):
                helper.parallel_http_listens(state)

    def test_unrecognized_primary_http_listener_fails_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            state = self.make_site(folder, (
                'server { listen 127.0.0.1:9443 ssl; server_name api.vline-secure.online; }'))
            with self.assertRaisesRegex(RuntimeError, 'HTTP-listener'):
                helper.parallel_http_listens(state)


if __name__ == '__main__':
    unittest.main()
