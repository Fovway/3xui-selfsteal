"""Hysteria 2 regressions: isolated API, no running services or network required."""
import json
from pathlib import Path
import types
import unittest
from unittest.mock import patch

SCRIPT=Path(__file__).resolve().parents[1] / "setup-selfsteal-3xui.sh"
source=SCRIPT.read_text().split("cat <<'PANEL_PY'\n",1)[1].split("\nPANEL_PY",1)[0]
helper=types.ModuleType("selfsteal_panel_helper_hysteria")
exec(compile(source,str(SCRIPT),"exec"),helper.__dict__)


class FakeApi:
    def __init__(self):
        self.rows=[{"id":10,"port":443,"protocol":"vless","tag":"reality",
                    "nodeId":None,"streamSettings":json.dumps(
                        {"network":"tcp","security":"reality"})}]
        self.serial=40
        self.created=[]
        self.deleted=[]
        self.restarts=0

    def list(self):
        return [dict(r) for r in self.rows]

    def call(self,path,data=None):
        if path=="panel/api/inbounds/add":
            self.serial+=1
            row=dict(data,id=self.serial)
            self.rows.append(row)
            self.created.append(row)
            return {"id":self.serial}
        if path.startswith("panel/api/inbounds/del/"):
            ident=int(path.rsplit("/",1)[1])
            self.rows=[row for row in self.rows if row["id"]!=ident]
            self.deleted.append(ident)
            return True
        raise AssertionError("Unexpected API call: "+path)

    def restart(self):
        self.restarts+=1

    def runtime_json(self):
        return json.dumps({"inbounds":[{
            "tag":r["tag"],"port":r["port"],"protocol":r["protocol"],
            "streamSettings":json.loads(r["streamSettings"]),
            "settings":json.loads(r["settings"]),
        } for r in self.created if r["id"] not in self.deleted]})


class FakeSocket:
    def bind(self,address):
        return None
    def close(self):
        return None


class HysteriaTests(unittest.TestCase):
    def setUp(self):
        self.api=FakeApi()
        self.state={"domain":"example.com","panel_url":"http://127.0.0.1:2053/hidden/",
                    "panel_username":"admin","panel_password":"test","inbound_id":10,
                    "panel_binary":"/usr/local/x-ui/x-ui"}
        self.saved=[]
        self.patches=[
            patch.object(helper,"verify",return_value=(self.api,None)),
            patch.object(helper.Path,"is_file",return_value=True),
            patch.object(helper.Path,"mkdir"),
            patch.object(helper.Path,"read_text",side_effect=lambda: self.api.runtime_json()),
            patch.object(helper,"secure_json"),
            patch.object(helper.socket,"socket",return_value=FakeSocket()),
            patch.object(helper.time,"sleep"),
            patch.object(helper.subprocess,"run",side_effect=self.command),
        ]
        for p in self.patches:
            p.start()
            self.addCleanup(p.stop)

    def command(self,args,**kwargs):
        if "checkhost" in args:
            return types.SimpleNamespace(returncode=0,stdout="Hostname example.com does match certificate\n")
        if args[0]=="ss":
            return types.SimpleNamespace(returncode=0,stdout='udp UNCONN 0 0 *:443 users:(("xray",pid=10))')
        return types.SimpleNamespace(returncode=0,stdout="")

    def save(self):
        self.saved.append(dict(self.state))

    def test_udp_443_can_coexist_with_tcp_443(self):
        helper.add_hysteria(self.state,443,"example.com",True,self.save)
        self.assertEqual(len(self.api.created),1)
        self.assertEqual(self.api.rows[0]["protocol"],"vless")
        self.assertEqual(self.api.created[0]["protocol"],"hysteria")
        self.assertEqual(json.loads(self.api.created[0]["settings"])["version"],2)
        self.assertEqual(self.state["hysteria_inbounds"][0]["port"],443)
        self.assertEqual(self.api.deleted,[])

    def test_more_than_one_hysteria_inbound_with_unique_auth(self):
        helper.add_hysteria(self.state,443,"example.com",True,self.save)
        helper.add_hysteria(self.state,8443,"example.com",True,self.save)
        self.assertEqual(len(self.api.created),2)
        self.assertEqual([x["port"] for x in self.api.created],[443,8443])
        auths=[json.loads(x["settings"])["clients"][0]["auth"] for x in self.api.created]
        masks=[json.loads(x["streamSettings"])["finalmask"]["udp"][0]["settings"]["password"] for x in self.api.created]
        self.assertEqual(len(set(auths)),2)
        self.assertEqual(len(set(masks)),2)
        self.assertEqual(len(self.state["hysteria_inbounds"]),2)

    def test_duplicate_udp_port_is_rejected_without_changes(self):
        helper.add_hysteria(self.state,443,"example.com",True,self.save)
        with self.assertRaisesRegex(RuntimeError,"UDP-порт"):
            helper.add_hysteria(self.state,443,"example.com",True,self.save)
        self.assertEqual(len(self.api.created),1)
        self.assertNotIn("pending_hysteria",self.state)

    def test_failure_removes_only_new_inbound(self):
        def missing_live_inbound():
            return json.dumps({"inbounds":[]})
        with patch.object(helper.Path,"read_text",side_effect=missing_live_inbound):
            with self.assertRaisesRegex(RuntimeError,"не подтвердил"):
                helper.add_hysteria(self.state,8443,"example.com",True,self.save)
        self.assertEqual(len(self.api.created),1)
        self.assertEqual(self.api.deleted,[self.api.created[0]["id"]])
        self.assertEqual(self.api.rows[0]["protocol"],"vless")
        self.assertNotIn("pending_hysteria",self.state)

    def test_salamander_can_be_disabled(self):
        helper.add_hysteria(self.state,9443,"example.com",False,self.save)
        self.assertNotIn("finalmask",json.loads(self.api.created[0]["streamSettings"]))


if __name__=="__main__":
    unittest.main()
