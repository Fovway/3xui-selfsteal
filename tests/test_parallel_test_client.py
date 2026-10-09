"""Regression checks for one synthetic client per independent Reality inbound."""
import json
from pathlib import Path
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-selfsteal-3xui.sh'
source = SCRIPT.read_text().split("cat <<'PANEL_PY'\n", 1)[1].split("\nPANEL_PY", 1)[0]
helper = types.ModuleType('parallel_test_client_helper')
exec(compile(source, str(SCRIPT), 'exec'), helper.__dict__)


class TestParallelTestClient(unittest.TestCase):
    def test_generated_test_accounts_have_unique_ids_and_no_limits(self):
        first = helper.parallel_generate_test_client(10455)
        second = helper.parallel_generate_test_client(10455)
        self.assertNotEqual(first['email'], second['email'])
        self.assertNotEqual(first['id'], second['id'])
        self.assertNotEqual(first['subId'], second['subId'])
        self.assertEqual(first['flow'], 'xtls-rprx-vision')
        self.assertTrue(first['enable'])
        self.assertEqual(first['totalGB'], 0)
        self.assertEqual(first['expiryTime'], 0)
        self.assertTrue(first['email'].startswith('selfsteal-test-10455-'))

    def test_confirmation_accepts_only_expected_uuid_subid_and_single_inbound(self):
        user = helper.parallel_generate_test_client(10501)
        class FakeApi:
            def __init__(self, inbound_ids, uuid=None):
                self.inbound_ids = inbound_ids
                self.uuid = uuid or user['id']
            def call(self, path):
                self_path = 'panel/api/clients/get/' + user['email']
                assert path == self_path
                return {'client': {'uuid': self.uuid, 'subId': user['subId'],
                                   'flow': 'xtls-rprx-vision'},
                        'inboundIds': self.inbound_ids}
        self.assertTrue(helper.parallel_confirm_test_client(FakeApi([21]), 21, user))
        for ids in ([22], [21, 22], []):
            with self.subTest(ids=ids), self.assertRaisesRegex(RuntimeError, 'изменён'):
                helper.parallel_confirm_test_client(FakeApi(ids), 21, user)
        with self.assertRaisesRegex(RuntimeError, 'изменён'):
            helper.parallel_confirm_test_client(FakeApi([21], uuid='changed'), 21, user)

    def test_runtime_checks_test_uuid_not_another_client(self):
        user = helper.parallel_generate_test_client(10456)
        state = {'runtime_config': '/tmp/dummy-xray-config.json',
                 'panel_binary': '/usr/local/x-ui/x-ui'}
        runtime = json.dumps({'inbounds': [{
            'tag': 'selfsteal-reality-10456', 'port': 10456,
            'settings': {'clients': [{'id': user['id'], 'flow': user['flow']}]}
        }]})
        with patch.object(helper.Path, 'read_text', return_value=runtime):
            helper.parallel_test_client_runtime(state, 'selfsteal-reality-10456', 10456, user)
        other = json.dumps({'inbounds': [{
            'tag': 'selfsteal-reality-10456', 'port': 10456,
            'settings': {'clients': [{'id': 'someone-else', 'flow': user['flow']}]}
        }]})
        with patch.object(helper.Path, 'read_text', return_value=other), \
             patch.object(helper.time, 'sleep'):
            with self.assertRaisesRegex(RuntimeError, 'не подтвердил'):
                helper.parallel_test_client_runtime(state, 'selfsteal-reality-10456', 10456, user)


if __name__ == '__main__':
    unittest.main()
