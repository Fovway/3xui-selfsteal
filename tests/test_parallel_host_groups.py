"""3x-ui HostGroup serialisation and subscription rollback regression tests."""
from pathlib import Path
import types
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-selfsteal-3xui.sh'
src = SCRIPT.read_text().split("cat <<'PANEL_PY'\n", 1)[1].split("\nPANEL_PY", 1)[0]
helper = types.ModuleType('host_group_helper')
exec(compile(src, str(SCRIPT), 'exec'), helper.__dict__)


class FakeHostsAPI:
    """Simulates 3x-ui v3.8.5: hosts/list includes :port on each address."""
    def __init__(self, groups=None):
        self.groups = [dict(row) for row in groups or []]
        self.operations = []

    @staticmethod
    def format_hosts(data):
        result = []
        for host in data['hosts']:
            # 3x-ui parses an explicit host port instead of appending twice.
            if host.rsplit(':', 1)[-1].isdigit():
                result.append(host)
            else:
                result.append(host + ':' + str(data.get('port') or 0))
        return result

    def call(self, path, data=None):
        self.operations.append((path, data))
        if path == 'panel/api/hosts/list':
            return [dict(row) for row in self.groups]
        if path == 'panel/api/hosts/add':
            group_id = (data.get('groupId') or 'generated-abc')
            row = dict(data, groupId=group_id,
                       hosts=self.format_hosts(data))
            self.groups.append(row)
            return [{'groupId': group_id}]
        if path.startswith('panel/api/hosts/update/'):
            group_id = path.rsplit('/', 1)[1]
            self.groups = [
                dict(data, groupId=group_id,
                     hosts=self.format_hosts(data))
                if g['groupId'] == group_id else g for g in self.groups]
            return []
        if path == 'panel/api/hosts/bulk/del':
            self.groups = [g for g in self.groups
                           if g['groupId'] not in data['ids']]
            return []
        raise AssertionError('Unexpected call ' + path)


class HostGroupRegressionTests(unittest.TestCase):
    def test_add_host_group_accepts_port_formatted_by_panel(self):
        api = FakeHostsAPI()
        ids = helper.parallel_hosts_apply(
            api, [{'id': 1, 'sni': 'api.example.com'}], [])
        self.assertEqual(ids, ['generated-abc'])
        self.assertEqual(api.groups[0]['hosts'], ['api.example.com:443'])
        self.assertEqual(api.groups[0]['inboundIds'], [1])
        self.assertEqual(api.groups[0]['port'], 443)

    def test_host_confirmation_rejects_wrong_domain_or_port(self):
        row = {'groupId': 'g1', 'inboundIds': [1], 'port': 443,
               'sni': 'api.example.com', 'hosts': ['other.example.com:443']}
        with self.assertRaisesRegex(RuntimeError, 'не подтверждена'):
            helper.parallel_host_confirm(1, 'api.example.com', row)

    def test_existing_group_preserves_metadata_and_id(self):
        prior = {'groupId': 'existing-1', 'inboundIds': [2],
                 'remark': 'billing-group', 'hosts': ['old.example.com:8443'],
                 'port': 8443, 'security': 'tls', 'sni': 'old.example.com',
                 'fingerprint': 'chrome', 'hostHeader': 'header.example.com',
                 'serverDescription': 'billing', 'isHidden': True,
                 'sortOrder': 4, 'alpn': ['h2'],
                 'excludeFromSubTypes': ['clash'], 'keepSniBlank': False,
                 'mihomoIpVersion': 'ipv4-prefer', 'finalMask': 'sample'}
        api = FakeHostsAPI([prior])
        created = helper.parallel_hosts_apply(
            api, [{'id': 2, 'sni': 'new.example.com'}], [prior])
        self.assertEqual(created, [])
        row = api.groups[0]
        self.assertEqual(row['groupId'], 'existing-1')
        self.assertEqual(row['hosts'], ['new.example.com:443'])
        for k in ('fingerprint', 'hostHeader', 'isHidden', 'sortOrder',
                  'alpn', 'serverDescription', 'excludeFromSubTypes',
                  'mihomoIpVersion', 'finalMask'):
            self.assertEqual(row[k], prior[k], k)

    def test_rollback_deletes_group_created_by_migration(self):
        api = FakeHostsAPI()
        helper.parallel_hosts_apply(api, [{'id': 1, 'sni': 'api.example.com'}], [])
        helper.parallel_hosts_restore(api, [{'id': 1}], [])
        self.assertEqual(api.groups, [])
        self.assertEqual(api.operations[-1][0], 'panel/api/hosts/bulk/del')

    def test_rollback_restores_original_group_and_fields(self):
        previous = {'groupId': 'prior', 'inboundIds': [2],
                    'remark': 'original', 'hosts': ['old.example.com:8443'],
                    'port': 8443, 'security': 'same', 'sni': '',
                    'isHidden': True, 'fingerprint': 'firefox'}
        api = FakeHostsAPI([previous])
        helper.parallel_hosts_apply(api, [{'id': 2, 'sni': 'new.example.com'}],
                                    [previous])
        helper.parallel_hosts_restore(api, [{'id': 2}], [previous])
        row = api.groups[0]
        self.assertEqual(row['hosts'], ['old.example.com:8443'])
        self.assertEqual(row['groupId'], 'prior')
        self.assertTrue(row['isHidden'])
        self.assertEqual(row['fingerprint'], 'firefox')

    def test_missing_rollback_group_restores_original_id(self):
        original = {'groupId': 'prior-abc', 'inboundIds': [2],
                    'remark': 'restored', 'port': 443,
                    'sni': 'api.example.com',
                    'hosts': ['api.example.com:443']}
        api = FakeHostsAPI()
        helper.parallel_hosts_restore(api, [{'id': 2}], [original])
        self.assertEqual(api.groups[0]['groupId'], 'prior-abc')


if __name__ == '__main__':
    unittest.main()
