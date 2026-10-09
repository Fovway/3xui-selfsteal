"""Read-only masking audit regression tests, no sockets or services contacted."""
import io
import json
from pathlib import Path
import types
import unittest
from unittest.mock import patch
from contextlib import redirect_stdout

SCRIPT=Path(__file__).resolve().parents[1]/'setup-selfsteal-3xui.sh'
source=SCRIPT.read_text()
start="python3 - \"$state_file\" <<'MASK_AUDIT_PY' | tee \"$report\"\n"
assert source.count(start)==1
embedded=source.split(start,1)[1].split('\nMASK_AUDIT_PY',1)[0]
audit=types.ModuleType('masking_audit')
exec(compile(embedded,str(SCRIPT),'exec'),audit.__dict__)


class MaskingAuditTests(unittest.TestCase):
    def setUp(self):
        audit.RESULTS.clear()

    def test_tcp_and_udp_listener_ports(self):
        raw="LISTEN 0 4096 127.0.0.1:2053 0.0.0.0:*\nLISTEN 0 4096 0.0.0.0:443 0.0.0.0:*\n"
        with patch.object(audit,'run_cmd',return_value=types.SimpleNamespace(returncode=0,stdout=raw)):
            self.assertEqual(audit.port_list('t'),[2053,443])
        raw="UNCONN 0 0 0.0.0.0:443 0.0.0.0:*\nUNCONN 0 0 [::]:8443 [::]:*\n"
        with patch.object(audit,'run_cmd',return_value=types.SimpleNamespace(returncode=0,stdout=raw)):
            self.assertEqual(audit.port_list('u'),[443,8443])

    def test_reality_ignores_hysteria_on_same_port(self):
        domain='example.com'
        reality={'id':1,'port':443,'protocol':'vless','tag':'reality',
                 'listen':'0.0.0.0','stream_settings':json.dumps({
                     'network':'tcp','security':'reality',
                     'realitySettings':{'serverNames':[domain],'target':'127.0.0.1:9443'}})}
        hy={'id':2,'port':443,'protocol':'hysteria','tag':'hy',
            'listen':'0.0.0.0','stream_settings':json.dumps({'network':'hysteria'})}
        live=[{'tag':'reality','protocol':'vless','streamSettings':{
            'realitySettings':{'serverNames':[domain],'target':'127.0.0.1:9443'}}}]
        with redirect_stdout(io.StringIO()):
            address=audit.inspect_reality({'domain':domain},[hy,reality],live,[443])
        self.assertEqual(address,'127.0.0.1')
        self.assertEqual(audit.RESULTS.count('FAIL'),0)

    def test_masking_output_redacts_secrets_and_control_sequences(self):
        with redirect_stdout(io.StringIO()) as output:
            audit.emit('WARN','Message','Bad\n\x1b[31mcontrol')
        self.assertNotIn('\nBad',output.getvalue())
        self.assertNotIn('\x1b',output.getvalue())
        self.assertIn('[WARN]',output.getvalue())

    def test_public_panel_flag_is_warn_not_false_claim(self):
        with redirect_stdout(io.StringIO()):
            audit.inspect_panel({'publish_panel':True,'panel_port':2053},
                                {'webListen':'127.0.0.1','webPort':'2053'},[2053])
        self.assertIn('WARN',audit.RESULTS)


if __name__=='__main__':
    unittest.main()
