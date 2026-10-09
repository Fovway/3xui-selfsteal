"""Add existing VLESS Reality inbound IDs to a working SNI stream without rewriting users."""
import copy
import json
from pathlib import Path
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-selfsteal-3xui.sh'
code = SCRIPT.read_text().split("cat <<'PANEL_PY'\n", 1)[1].split("\nPANEL_PY", 1)[0]
helper = types.ModuleType('adopt_helper')
exec(compile(code, str(SCRIPT), 'exec'), helper.__dict__)


class ExistingAdoptionTests(unittest.TestCase):
    def setUp(self):
        self.primary_sni='api.vline-secure.online'
        self.map={'2':'api2.vline-secure.online','3':'api3.vline-secure.online'}
        self.state={'domain':self.primary_sni,'reality_mode':'parallel',
                    'inbound_id':1,'primary_internal_port':10443,
                    'parallel_sni_by_id':{'1':self.primary_sni},
                    'added_inbounds':[],'target_port':9443}
        def row(id,port,sni):
            return dict(id=id,port=port,listen='127.0.0.1',
                tag=f'in-{port}-tcp',enable=True,protocol='vless',
                settings=json.dumps({'clients':[{'id':f'uuid-{id}','email':f'user-{id}'}]}),
                streamSettings=json.dumps({'network':'tcp','security':'reality',
                    'tcpSettings':{'acceptProxyProtocol':id==1},
                    'realitySettings':{
                        'privateKey':f'original-key-{id}','shortIds':[f'aa{id}'],
                        'serverNames':[sni],'target':'127.0.0.1:9443','xver':1}}))
        self.primary=row(1,10443,self.primary_sni)
        self.old2=row(2,8443,self.primary_sni)
        self.old3=row(3,8444,self.primary_sni)
        self.rows=[self.primary,self.old2,self.old3,
                   {'id':8,'port':443,'protocol':'hysteria','listen':''}]

    def test_projection_keeps_existing_users_and_private_keys(self):
        api=type('FakeAPI',(),{'list':lambda _:copy.deepcopy(self.rows),
                     'call':lambda *args:[]})()
        listeners=''.join(
            f'LISTEN 0 4096 127.0.0.1:{p} 0.0.0.0:* users:(("xray-linux-amd64",pid=13,fd=4))\n'
            for p in (8443,8444))
        process=type('Proc',(),{'stdout':listeners})()
        with patch.object(helper,'require_version'), \
             patch.object(helper,'parallel_existing_rows',return_value=[
                  {'id':1,'sni':self.primary_sni,'port':10443,
                   'before':self.primary,'after':self.primary}]), \
             patch.object(helper,'parallel_dns_check'), \
             patch.object(helper,'parallel_texts'), \
             patch.object(helper.subprocess,'run',return_value=process):
            old, planned, groups=helper.parallel_adopt_plan(self.state,self.map,api)
        self.assertEqual(len(planned),2)
        self.assertEqual({x['id'] for x in planned},{2,3})
        for r in planned:
            b,a=r['before'],r['after']
            self.assertEqual(b['settings'],a['settings'])
            old_reality=json.loads(b['streamSettings'])['realitySettings']
            new_reality=json.loads(a['streamSettings'])['realitySettings']
            self.assertEqual(old_reality['privateKey'],new_reality['privateKey'])
            self.assertEqual(old_reality['shortIds'],new_reality['shortIds'])
            self.assertEqual(new_reality['serverNames'],[r['sni']])
            self.assertTrue(json.loads(a['streamSettings'])['tcpSettings']['acceptProxyProtocol'])

    def test_refuses_reusing_occupied_primary_sni(self):
        api=type('FakeAPI',(),{'list':lambda _:copy.deepcopy(self.rows),
                               'call':lambda *args:[]})()
        with patch.object(helper,'require_version'), \
             patch.object(helper,'parallel_existing_rows',return_value=[
                  {'id':1,'sni':self.primary_sni,'port':10443,
                   'before':self.primary,'after':self.primary}]):
            with self.assertRaisesRegex(RuntimeError,'уже занят'):
                helper.parallel_adopt_plan(self.state,{'2':self.primary_sni},api)

    def test_refuses_foreign_or_shared_hosts_group(self):
        api=type('FakeAPI',(),{
            'list':lambda _:copy.deepcopy(self.rows),
            'call':lambda *args:[{'groupId':'shared','inboundIds':[1,2]}]})()
        with patch.object(helper,'require_version'), \
             patch.object(helper,'parallel_existing_rows',return_value=[
                  {'id':1,'sni':self.primary_sni,'port':10443,
                   'before':self.primary,'after':self.primary}]):
            with self.assertRaisesRegex(RuntimeError,'общую/неоднозначную'):
                helper.parallel_adopt_plan(self.state,{'2':self.map['2']},api)

    def test_refuses_public_bound_candidate(self):
        self.rows[1]['listen']='0.0.0.0'
        api=type('FakeAPI',(),{'list':lambda _:copy.deepcopy(self.rows),
                               'call':lambda *args:[]})()
        with patch.object(helper,'require_version'), \
             patch.object(helper,'parallel_existing_rows',return_value=[
                  {'id':1,'sni':self.primary_sni,'port':10443,
                   'before':self.primary,'after':self.primary}]):
            with self.assertRaisesRegex(RuntimeError,'loopback'):
                helper.parallel_adopt_plan(self.state,{'2':self.map['2']},api)

    def test_dns_preflight_does_not_touch_services(self):
        api=type('FakeAPI',(),{'list':lambda _:copy.deepcopy(self.rows),
                               'call':lambda *args:[]})()
        with patch.object(helper,'require_version'), \
             patch.object(helper,'parallel_existing_rows',return_value=[
                  {'id':1,'sni':self.primary_sni,'port':10443,
                   'before':self.primary,'after':self.primary}]), \
             patch.object(helper,'parallel_dns_check',side_effect=RuntimeError('DNS mismatch')), \
             patch.object(helper.subprocess,'run',side_effect=AssertionError('must not restart')):
            with self.assertRaisesRegex(RuntimeError,'DNS mismatch'):
                helper.parallel_adopt_plan(self.state,{'2':self.map['2']},api)


if __name__=='__main__':
    unittest.main()
