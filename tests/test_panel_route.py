"""Regression checks for the nginx reload transition; no system services are touched."""
from pathlib import Path
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-selfsteal-3xui.sh'
source = SCRIPT.read_text().split("cat <<'PANEL_PY'\n", 1)[1].split('\nPANEL_PY', 1)[0]
helper = types.ModuleType('selfsteal_panel_helper')
exec(compile(source, str(SCRIPT), 'exec'), helper.__dict__)
TOKEN = b'{"success":true,"obj":"token"}'


class ReloadTransitionTests(unittest.TestCase):
    def setUp(self):
        self.elapsed = 0.0
        self.clock = patch.object(helper.time, 'monotonic', side_effect=lambda: self.elapsed)
        self.sleep = patch.object(helper.time, 'sleep', side_effect=self.advance)
        self.clock.start()
        self.sleep.start()
        self.addCleanup(self.clock.stop)
        self.addCleanup(self.sleep.stop)

    def advance(self, duration):
        self.elapsed += duration

    def test_disable_waits_for_old_workers_to_stop_serving_panel(self):
        with patch.object(helper, 'panel_route_response', side_effect=[(200, TOKEN), (200, TOKEN), (404, b'not found')]) as probe:
            helper.check_panel_route({}, False)
        self.assertEqual(probe.call_count, 3)

    def test_enable_waits_for_new_workers_to_serve_panel(self):
        with patch.object(helper, 'panel_route_response', side_effect=[(404, b'not found'), (200, TOKEN)]):
            helper.check_panel_route({}, True)

    def test_reachable_panel_is_never_accepted_as_closed(self):
        with patch.object(helper, 'panel_route_response', return_value=(200, TOKEN)):
            with self.assertRaisesRegex(RuntimeError, 'закрытие.*HTTP 200'):
                helper.check_panel_route({}, False)
        self.assertEqual(self.elapsed, 15)

    def test_temporary_socket_failure_during_reload_is_retried(self):
        with patch.object(helper, 'panel_route_response', side_effect=[ConnectionResetError(), (404, b'not found')]):
            helper.check_panel_route({}, False)

    def test_static_json_is_not_mistaken_for_live_panel(self):
        with patch.object(helper, 'panel_route_response', return_value=(200, b'[]')):
            with self.assertRaisesRegex(RuntimeError, 'открытие.*HTTP 200'):
                helper.check_panel_route({}, True)


if __name__ == '__main__':
    unittest.main()
