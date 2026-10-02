#!/usr/bin/env bash
# Interactive, fail-closed self-steal Reality setup; official 3x-ui v3.8.5.
set -Eeuo pipefail
umask 077
VERSION=3.8.5
# Network checks must observe this machine, not an inherited proxy.
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY
CHECK=0
DOMAIN=''
while (( $# )); do
  case $1 in
    --help|-h) cat <<'HELP'
Usage: sudo bash setup-selfsteal-3xui.sh [--check [--domain HOSTNAME]]
Interactive Ubuntu/Debian systemd setup; no environment variables required.
--check performs read-only inspection and DNS/conflict checks without credentials.
Missing preflight utilities can be installed with separate explicit consent.
These packages are retained if later validation fails; --check never installs.
Existing3x-ui administrators/clients are preserved. Fresh panels are loopback-only.
Private results/backups are saved under /root/selfsteal-3xui/.
HELP
      exit 0 ;;
    --check) CHECK=1; shift ;;
    --domain) [[ $# -ge 2 ]] || { echo 'Missing domain' >&2; exit 2; }; DOMAIN=$2; shift 2 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ -z $DOMAIN || $CHECK == 1 ]] || { echo '--domain is only supported with --check' >&2; exit 2; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ $EUID == 0 ]] || fail 'Run with sudo bash.'
[[ -r /etc/os-release ]] || fail 'Missing OS identification.'
. /etc/os-release
[[ $ID == ubuntu || $ID == debian ]] || fail 'Only Ubuntu and Debian are supported.'
[[ -d /run/systemd/system ]] || fail 'A running systemd host is required.'
command -v systemctl >/dev/null || fail 'systemctl is missing; only a running systemd host is supported.'
(( CHECK )) || [[ -t 0 ]] || fail 'An interactive terminal is required.'
PREFLIGHT_PACKAGES=()
command -v python3 >/dev/null || PREFLIGHT_PACKAGES+=(python3)
if ! command -v ss >/dev/null || ! command -v ip >/dev/null; then PREFLIGHT_PACKAGES+=(iproute2); fi
command -v flock >/dev/null || PREFLIGHT_PACKAGES+=(util-linux)
if (( ${#PREFLIGHT_PACKAGES[@]} )); then
  (( ! CHECK )) || fail "Read-only check cannot proceed: missing preflight packages: ${PREFLIGHT_PACKAGES[*]}. No package installation attempted."
  command -v apt-get >/dev/null || fail 'apt-get is unavailable on this system.'
  printf 'Minimal preflight utilities are missing. Install ONLY: %s\n' "${PREFLIGHT_PACKAGES[*]}"
  echo 'This preliminary installation does not configure nginx/panel/firewall. Packages are retained, not rolled back, if any later preflight/setup fails.'
  read -r -p 'Type INSTALL PREFLIGHT PACKAGES to consent (otherwise cancel): ' ANSWER
  [[ $ANSWER == 'INSTALL PREFLIGHT PACKAGES' ]] || fail 'Cancelled before dependency installation.'
  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PREFLIGHT_PACKAGES[@]}"
  for command in python3 ss ip flock; do command -v "$command" >/dev/null || fail "Preflight utility $command still unavailable after package installation."; done
fi
# Lock an existing inode: even --check creates no lock file.
exec 9</etc/os-release
flock -n 9 || fail 'Another setup is running.'
WORK=$(mktemp -d /tmp/selfsteal-3xui.XXXXXXXX)
STATE=$WORK/state.json
PANEL_HELPER=$WORK/panel.py
MUTATED=0
SUCCESS=0
SMOKE_PID=''
BACKUP=''
FRESH_FILES=0
FRESH_ROOT=0
UFW_WAS_ACTIVE=0
if command -v ufw >/dev/null && ufw status | python3 -c 'import sys; sys.exit(0 if "Status: active" in sys.stdin.read() else 1)'; then UFW_WAS_ACTIVE=1; fi
FILES=()
SERVICES=(nginx x-ui fail2ban certbot.timer)
declare -A WAS_ACTIVE WAS_ENABLED
emit_panel_helper() {
cat <<'PANEL_PY'
#!/usr/bin/env python3
"""Pinned 3x-ui 3.8.5 helper. Never logs credentials or private configuration."""
import argparse
import base64
import copy
import ctypes
import ctypes.util
import http.cookiejar
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import socket
import sqlite3
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import uuid

VERSION = '3.8.5'


def secure_json(path, value):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.tmp-' + secrets.token_hex(6))
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as f:
        json.dump(value, f, indent=2)
        f.write('\n')
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
    os.chmod(path, 0o600)


def parse(value):
    return json.loads(value) if isinstance(value, str) else value


def run(args, state):
    env = os.environ.copy()
    env['XUI_DB_FOLDER'] = str(Path(state['panel_db']).parent)
    env['XUI_BIN_FOLDER'] = str(Path(state['panel_binary']).parent / 'bin')
    env['XUI_DB_TYPE'] = 'sqlite'
    p = subprocess.run(args, env=env, cwd=Path(state['panel_binary']).parent,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if p.returncode:
        raise RuntimeError('3x-ui CLI operation failed (output withheld to protect secrets)')
    return p.stdout


def require_version(state):
    version = run([state['panel_binary'], '-v'], state).strip().removeprefix('v')
    if version != VERSION:
        raise RuntimeError('Unsupported 3x-ui version: only verified 3.8.5 is supported; no upgrade performed')
    state['panel_version'] = version


def db_read(state):
    return sqlite3.connect(Path(state['panel_db']).as_uri() + '?mode=ro', uri=True)


def inspect(state):
    exists = Path(state['panel_db']).exists()
    binary = Path(state['panel_binary']).exists()
    if exists != binary:
        raise RuntimeError('Partial 3x-ui installation detected; resolve it before setup')
    state['is_existing'] = exists
    matches = []
    if exists:
        require_version(state)
        with db_read(state) as db:
            settings = dict(db.execute('SELECT key,value FROM settings'))
            db.row_factory = sqlite3.Row
            inbounds = [dict(r) for r in db.execute('SELECT * FROM inbounds WHERE port=443 AND (node_id IS NULL OR node_id=0)')]
        for row in inbounds:
            stream = parse(row['stream_settings'])
            if row['protocol'] != 'vless' or stream.get('security') != 'reality':
                raise RuntimeError('Existing local panel inbound443 is incompatible; nothing changed')
            if stream.get('network') not in ('tcp', 'raw'):
                raise RuntimeError('Existing Reality443 transport is not TCP/raw; migration would break clients')
            if row.get('disable_flow'):
                raise RuntimeError('Existing inbound disables all client flows; cannot add Vision without changing old clients')
            matches.append(row)
        if len(matches) > 1:
            raise RuntimeError('Multiple local443 inbounds require manual reconciliation')
        if settings.get('webListen', '') not in ('127.0.0.1', '::1'):
            raise RuntimeError('Existing panel is not loopback-only. Restrict its listener explicitly before setup; admin settings will not be changed')
        if any(settings.get(k, 'false') == 'true' for k in ('subEnable', 'subJsonEnable', 'subClashEnable')) and settings.get('subListen', '') not in ('127.0.0.1', '::1'):
            raise RuntimeError('Existing subscription listener is public; restrict explicitly before setup')
        if not state.get('panel_url'):
            host = settings.get('webListen', '127.0.0.1')
            host = '[' + host + ']' if ':' in host else host
            scheme = 'https' if settings.get('webCertFile') and settings.get('webKeyFile') else 'http'
            base_path = '/' + settings.get('webBasePath', '/').strip('/')
            if base_path != '/':
                base_path += '/'
            state['panel_url'] = '%s://%s:%s%s' % (scheme, host, settings.get('webPort', '2053'), base_path)
        state['inbound_id'] = matches[0]['id'] if matches else None
    else:
        state['inbound_id'] = None
    ss = subprocess.run(['ss', '-H', '-ltnp', 'sport = :443'], capture_output=True, text=True, check=True).stdout
    if ss.strip() and not matches:
        raise RuntimeError('TCP443 is occupied outside a compatible local3x-ui Reality inbound; no service will be killed')
    if ss.strip() and any('xray' not in line.lower() for line in ss.splitlines()):
        raise RuntimeError('TCP443 listener owner is not verifiably Xray; refusing takeover')


def bcrypt_password(password):
    libname = ctypes.util.find_library('crypt')
    if not libname:
        raise RuntimeError('libcrypt with bcrypt support is required for secure bootstrap')
    lib = ctypes.CDLL(libname)
    lib.crypt.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    lib.crypt.restype = ctypes.c_char_p
    # bcrypt salt uses its own alphabet; 22 chars represent 128 bits.
    alphabet = './ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    salt = ''.join(secrets.choice(alphabet) for _ in range(21)) + secrets.choice('.Oeu')
    hashed = lib.crypt(password.encode(), ('$2b$12$' + salt).encode())
    if not hashed or not hashed.startswith(b'$2b$12$') or len(hashed) != 60:
        raise RuntimeError('System libcrypt cannot generate bcrypt; safe bootstrap stopped')
    return hashed.decode()


def bootstrap(state):
    if state.get('is_existing') or Path(state['panel_db']).exists():
        raise RuntimeError('Bootstrap is fresh-only; existing credentials will never be reset')
    require_version(state)
    port = int(state.get('panel_port', 2053))
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', port))
    username = 'admin_' + secrets.token_hex(10)
    password = secrets.token_urlsafe(36)
    hashed = bcrypt_password(password)
    path = '/' + secrets.token_urlsafe(24) + '/'
    Path(state['panel_db']).parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    run([state['panel_binary'], 'setting', '-listenIP', '127.0.0.1', '-port', str(port), '-webBasePath', path], state)
    # Only this newly initialized, never-started DB is written directly. The CLI
    # has no password-on-stdin interface; this avoids credentials in process argv.
    os.chmod(state['panel_db'], 0o600)
    with sqlite3.connect(state['panel_db']) as db:
        if db.execute('SELECT count(*) FROM users').fetchone()[0] != 1:
            raise RuntimeError('Unexpected fresh administrator count; service must remain stopped')
        db.execute('UPDATE users SET username=?, password=?', (username, hashed))
        for key, value in {'webListen': '127.0.0.1', 'webPort': str(port), 'webBasePath': path,
                           'subEnable': 'false', 'subJsonEnable': 'false', 'subClashEnable': 'false',
                           'subListen': '127.0.0.1'}.items():
            if db.execute('SELECT count(*) FROM settings WHERE key=?', (key,)).fetchone()[0]:
                db.execute('UPDATE settings SET value=? WHERE key=?', (value, key))
            else:
                db.execute('INSERT INTO settings(key,value) VALUES (?,?)', (key, value))
        saved = dict(db.execute('SELECT key,value FROM settings'))
        if saved['webListen'] != '127.0.0.1' or any(saved[k] != 'false' for k in ('subEnable', 'subJsonEnable', 'subClashEnable')):
            raise RuntimeError('Fresh bootstrap safety verification failed')
    state.update(panel_username=username, panel_password=password, panel_port=port,
                 panel_url='http://127.0.0.1:%d%s' % (port, path), bootstrap_complete=True)


class API:
    def __init__(self, state):
        self.base = state['panel_url'].rstrip('/') + '/'
        url = urllib.parse.urlsplit(self.base)
        if url.scheme not in ('http', 'https') or not url.hostname or not ipaddress.ip_address(url.hostname).is_loopback or url.username or url.password or url.query or url.fragment:
            raise RuntimeError('Panel API URL must be a literal loopback origin and basePath')
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        self.token = None
        self.token = self.call('csrf-token')
        self.call('login', {'username': state['panel_username'], 'password': state['panel_password'],
                            'twoFactorCode': state.get('panel_two_factor_code', '')})
        self.token = self.call('csrf-token')

    def call(self, path, data=None):
        headers = {'Accept': 'application/json'}
        if self.token:
            headers['X-CSRF-Token'] = self.token
        raw = None
        if data is not None:
            headers['Content-Type'] = 'application/json'
            raw = json.dumps(data).encode()
        req = urllib.request.Request(self.base + path, data=raw, headers=headers)
        try:
            with self.opener.open(req, timeout=30) as response:
                obj = json.load(response)
        except Exception:
            raise RuntimeError('Panel API request failed at ' + path + ' (credentials/configuration withheld)') from None
        if not obj.get('success'):
            raise RuntimeError('Panel API rejected ' + path + ' (response withheld)')
        return obj.get('obj')

    def list(self):
        return self.call('panel/api/inbounds/list') or []

    def restart(self):
        self.call('panel/api/server/restartXrayService', {})


def public_key(private):
    key = base64.urlsafe_b64decode(private + '=' * (-len(private) % 4))
    if len(key) != 32:
        raise RuntimeError('Reality private key is not a32-byte X25519 key')
    # RFC8410 PKCS8/SPKI encoding. OpenSSL receives private material only on
    # stdin, never in argv, environment, a temporary file, or diagnostics.
    der = bytes.fromhex('302e020100300506032b656e04220420') + key
    result = subprocess.run(['openssl', 'pkey', '-inform', 'DER', '-pubout', '-outform', 'DER'],
                            input=der, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    prefix = bytes.fromhex('302a300506032b656e032100')
    if result.returncode or not result.stdout.startswith(prefix) or len(result.stdout) != len(prefix) + 32:
        raise RuntimeError('OpenSSL X25519 public-key derivation failed')
    return base64.urlsafe_b64encode(result.stdout[len(prefix):]).decode().rstrip('=')


def pick(inbounds):
    matches = [i for i in inbounds if i.get('port') == 443 and not i.get('nodeId')]
    if len(matches) > 1:
        raise RuntimeError('Multiple local443 inbounds are unsupported')
    if matches and (matches[0]['protocol'] != 'vless' or parse(matches[0]['streamSettings']).get('security') != 'reality'):
        raise RuntimeError('Local443 inbound is incompatible')
    if matches and parse(matches[0]['streamSettings']).get('network') not in ('tcp', 'raw'):
        raise RuntimeError('Existing Reality443 transport is not TCP/raw; migration would break clients')
    if matches and matches[0].get('disableFlow'):
        raise RuntimeError('Existing inbound disables all client flows; cannot add Vision without changing old clients')
    return matches[0] if matches else None


def authenticate(state):
    require_version(state)
    api = API(state)
    snapshot_clients(api, pick(api.list()))


def payload(inbound):
    return {k: v for k, v in inbound.items() if k not in ('clientStats', 'fallbackParent')}


def canonical_client(api, email):
    return api.call('panel/api/clients/get/' + urllib.parse.quote(email, safe=''))


def client_update_payload(snapshot):
    # GET returns ClientRecord: numeric row id, uuid, camelCase timestamps,
    # JSON-text allowedIPs. POST expects model.Client, not ClientRecord.
    record = snapshot['client']
    fields = ('security', 'password', 'auth', 'flow', 'privateKey', 'publicKey',
              'preSharedKey', 'keepAlive', 'forwardedPorts', 'secret', 'adTag',
              'email', 'limitIp', 'limitHwid', 'totalGB', 'expiryTime', 'enable',
              'tgId', 'subId', 'group', 'comment', 'reset', 'resetDay',
              'resetMax', 'trafficReset', 'trafficResetDay')
    result = {key: copy.deepcopy(record[key]) for key in fields if key in record}
    result['id'] = record['uuid']
    allowed = record.get('allowedIPs') or []
    allowed = json.loads(allowed) if isinstance(allowed, str) else allowed
    if not isinstance(allowed, list) or any(not isinstance(ip, str) for ip in allowed):
        raise RuntimeError('Canonical allowedIPs does not match verified model.Client schema')
    result['allowedIPs'] = allowed
    reverse = record.get('reverse') or None
    result['reverse'] = parse(reverse) if isinstance(reverse, str) else reverse
    result['created_at'] = record.get('createdAt', 0)
    result['updated_at'] = record.get('updatedAt', 0)
    tunnel_ips = snapshot.get('tunnelAllowedIPs')
    if tunnel_ips:
        result['allowedIPsByInbound'] = copy.deepcopy(tunnel_ips)
    return result


def client_behavior(snapshot):
    result = client_update_payload(snapshot)
    result.pop('created_at', None)
    result.pop('updated_at', None)
    return result


def snapshot_clients(api, inbound):
    snapshots = []
    if inbound:
        for client in parse(inbound['settings']).get('clients', []):
            snapshot = canonical_client(api, client['email'])
            client_update_payload(snapshot)  # Validate rollback schema before mutation.
            if not client.get('flow') and snapshot['client'].get('flow') == 'xtls-rprx-vision':
                raise RuntimeError('Empty inbound flow conflicts with canonical intended Vision flow; resolve explicitly before setup')
            snapshots.append(snapshot)
    return snapshots


def configure(state, save):
    require_version(state)
    api = API(state)
    before = api.list()
    old = pick(before)
    canonical_before = snapshot_clients(api, old)
    backup = Path(state['backup_dir'])
    backup.mkdir(mode=0o700, parents=True, exist_ok=True)
    with db_read(state) as db, sqlite3.connect(backup / 'panel-before.db') as dest:
        db.backup(dest)
    os.chmod(backup / 'panel-before.db', 0o600)
    secure_json(backup / 'panel-api-before.json', before)
    state['panel_rollback'] = {'inbound': old, 'canonical_clients': canonical_before,
                               'created_client': None, 'created_id': None,
                               'pending_create': old is None}
    save()
    if old:
        inbound = copy.deepcopy(old)
        settings = parse(inbound['settings'])
        stream = parse(inbound['streamSettings'])
        reality = stream.get('realitySettings', {})
        if not reality.get('privateKey') or not reality.get('shortIds'):
            raise RuntimeError('Existing Reality key/shortIds missing; will not regenerate identities')
    else:
        private = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip('=')
        settings = {'clients': [{'id': str(uuid.uuid4()), 'flow': 'xtls-rprx-vision', 'email': 'selfsteal-' + secrets.token_hex(5), 'enable': True, 'limitIp': 0, 'totalGB': 0, 'expiryTime': 0, 'subId': secrets.token_hex(8), 'reset': 0}], 'decryption': 'none', 'fallbacks': []}
        reality = {'show': False, 'privateKey': private, 'shortIds': [secrets.token_hex(8)]}
        stream = {}
        inbound = {'remark': 'selfsteal-reality', 'enable': True, 'expiryTime': 0, 'total': 0,
                   'up': 0, 'down': 0, 'port': 443, 'protocol': 'vless', 'listen': '',
                   'tag': 'selfsteal-reality-443', 'trafficReset': 'never', 'trafficResetDay': 1,
                   'sniffing': json.dumps({'enabled': True, 'destOverride': ['http', 'tls', 'quic'], 'routeOnly': True})}
    clients = settings.get('clients', [])
    if not any(c.get('flow') == 'xtls-rprx-vision' and client_active(c, inbound) for c in clients):
        clients.append({'id': str(uuid.uuid4()), 'flow': 'xtls-rprx-vision',
                        'email': 'selfsteal-' + secrets.token_hex(5), 'enable': True,
                        'limitIp': 0, 'totalGB': 0, 'expiryTime': 0,
                        'subId': secrets.token_hex(8), 'reset': 0})
        settings['clients'] = clients
    original_ids = {c['id'] for c in parse(old['settings']).get('clients', [])} if old else set()
    added = [c for c in clients if c['id'] not in original_ids]
    if added:
        created_client = added[0]
        existing_clients = api.call('panel/api/clients/list') or []
        if any(c.get('email') == created_client['email'] or c.get('uuid') == created_client['id'] for c in existing_clients):
            raise RuntimeError('New script client identity collision; nothing changed')
        state['panel_rollback']['created_client'] = {
            'email': created_client['email'], 'uuid': created_client['id'],
            'subId': created_client['subId']}
        save()
    domain = state['domain']
    reality.update(target='127.0.0.1:%d' % int(state.get('target_port', 9443)), serverNames=[domain], xver=1)
    reality.pop('dest', None)
    reality.setdefault('settings', {}).update(publicKey=public_key(reality['privateKey']), fingerprint='chrome', serverName=domain, spiderX='/')
    stream.update(network='tcp', security='reality', realitySettings=reality, tcpSettings={'header': {'type': 'none'}})
    # Remove incompatible transport-specific structures during canonical TCP cutover.
    for key in ('rawSettings', 'wsSettings', 'grpcSettings', 'xhttpSettings', 'httpupgradeSettings', 'kcpSettings'):
        stream.pop(key, None)
    inbound.update(settings=json.dumps(settings), streamSettings=json.dumps(stream), shareAddrStrategy='custom', shareAddr=domain)
    if not old:
        inbound['disableFlow'] = False
    try:
        if old:
            api.call('panel/api/inbounds/update/%s' % old['id'], payload(inbound))
        else:
            created = api.call('panel/api/inbounds/add', payload(inbound))
            state['panel_rollback']['created_id'] = created['id']
            state['panel_rollback']['pending_create'] = False
            save()
        state['inbound_id'] = pick(api.list())['id']
        save()
        api.restart()
        verify(state)
    except Exception:
        rollback(state)
        raise


def rollback(state):
    record = state.get('panel_rollback')
    if not record:
        return
    api = API(state)
    old = record.get('inbound')
    if old:
        for snapshot in record.get('canonical_clients', []):
            email = snapshot['client']['email']
            current = canonical_client(api, email)
            if client_behavior(current) != client_behavior(snapshot):
                restored = client_update_payload(snapshot)
                original = next(c for c in parse(old['settings'])['clients'] if c['email'] == email)
                restored['flow'] = original.get('flow', '')
                api.call('panel/api/clients/update/%s?inboundIds=%s' % (
                    urllib.parse.quote(email, safe=''), old['id']), restored)
    created_client = record.get('created_client')
    if created_client:
        candidates = [c for c in (api.call('panel/api/clients/list') or [])
                      if c.get('email') == created_client['email']]
        if candidates:
            owned_id = old['id'] if old else record.get('created_id')
            if owned_id is None and record.get('pending_create'):
                found = pick(api.list())
                owned_id = found['id'] if found and found.get('tag') == 'selfsteal-reality-443' else None
            candidate = candidates[0]
            if (len(candidates) != 1 or candidate.get('uuid') != created_client['uuid']
                    or candidate.get('subId') != created_client['subId']
                    or any(i != owned_id for i in candidate.get('inboundIds') or [])):
                raise RuntimeError('Created-client ownership changed; refusing destructive rollback cleanup')
            # Proven ClientService.Delete endpoint removes this unique global
            # record and its associations. No preexisting client is targeted.
            api.call('panel/api/clients/del/' + urllib.parse.quote(created_client['email'], safe=''), {})
    if old:
        api.call('panel/api/inbounds/update/%s' % old['id'], payload(old))
    else:
        created = record.get('created_id')
        if created is None and record.get('pending_create'):
            found = pick(api.list())
            if found and found.get('tag') == 'selfsteal-reality-443':
                created = found['id']
        if created:
            api.call('panel/api/inbounds/del/%s' % created, {})
    api.restart()
    state.pop('panel_rollback', None)


def client_active(client, inbound):
    stats = {s['email']: s.get('enable', True) for s in inbound.get('clientStats', [])}
    expiry = client.get('expiryTime', 0)
    return (client.get('enable', True) and stats.get(client.get('email'), True)
            and (expiry <= 0 or expiry > int(time.time() * 1000)))


def checked_uri(api, state, inbound):
    settings = parse(inbound['settings'])
    active = [c for c in settings['clients'] if c.get('flow') == 'xtls-rprx-vision' and client_active(c, inbound)]
    if not active:
        raise RuntimeError('No active client is available for export and smoke')
    reality = parse(inbound['streamSettings'])['realitySettings']
    expected_key = public_key(reality['privateKey'])
    links = api.call('panel/api/inbounds/allLinks') or []
    for client in active:
        for link in links:
            url = urllib.parse.urlsplit(link)
            if url.scheme != 'vless' or url.username != client['id'] or url.hostname != state['domain'] or url.port != 443:
                continue
            q = urllib.parse.parse_qs(url.query, keep_blank_values=True)
            expected = {'security': 'reality', 'type': 'tcp', 'flow': 'xtls-rprx-vision', 'sni': state['domain'], 'pbk': expected_key}
            if any(q.get(k) != [v] for k, v in expected.items()) or q.get('sid', [''])[0] not in reality['shortIds']:
                continue
            if not q.get('fp'):
                continue
            return link, client, q
    raise RuntimeError('Actual panel link generator did not produce the required domain/Vision/Reality identity; refusing fabricated export')


def verify(state):
    require_version(state)
    api = API(state)
    inbound = pick(api.list())
    if not inbound or inbound['id'] != state.get('inbound_id'):
        raise RuntimeError('Configured local443 inbound not found')
    stream = parse(inbound['streamSettings'])
    reality = stream['realitySettings']
    target = '127.0.0.1:%d' % int(state.get('target_port', 9443))
    if stream.get('network') != 'tcp' or reality.get('target') != target or reality.get('xver') != 1 or reality.get('serverNames') != [state['domain']] or inbound.get('shareAddrStrategy') != 'custom' or inbound.get('shareAddr') != state['domain']:
        raise RuntimeError('Panel API Reality configuration verification failed')
    checked_uri(api, state, inbound)
    # Runtime file is the consumed bundled-Xray configuration, not just DB state.
    runtime_path = Path(state.get('runtime_config', str(Path(state['panel_binary']).parent / 'bin/config.json')))
    runtime = None
    for _ in range(30):
        try:
            runtime = json.loads(runtime_path.read_text())
            rows = [r for r in runtime.get('inbounds', []) if r.get('port') == 443 and r.get('tag') == inbound['tag']]
            if rows:
                rs = rows[0].get('streamSettings', {}).get('realitySettings', {})
                if rs.get('target', rs.get('dest')) == target and rs.get('privateKey') == reality['privateKey'] and rs.get('shortIds') == reality['shortIds'] and rs.get('serverNames') == [state['domain']] and rs.get('xver') == 1:
                    stats = {s['email']: s.get('enable', True) for s in inbound.get('clientStats', [])}
                    expected = set()
                    for client in parse(inbound['settings'])['clients']:
                        if not client.get('enable', True) or not stats.get(client.get('email'), True):
                            continue
                        flow = client.get('flow', '')
                        if flow == 'xtls-rprx-vision-udp443':
                            flow = 'xtls-rprx-vision'
                        if inbound.get('disableFlow'):
                            flow = ''
                        expected.add((client['id'], flow))
                    actual = {(c['id'], c.get('flow', '')) for c in rows[0]['settings'].get('clients', [])}
                    if expected == actual:
                        break
        except (OSError, ValueError, KeyError):
            pass
        time.sleep(1)
    else:
        raise RuntimeError('Bundled Xray consumed configuration does not match preserved API identities')
    if not state.get('is_existing'):
        settings = api.call('panel/api/setting/all', {})
        if settings.get('webListen') != '127.0.0.1' or any(settings.get(k) for k in ('subEnable', 'subJsonEnable', 'subClashEnable')):
            raise RuntimeError('Fresh panel listener/subscription safety verification failed')
    return api, inbound


def export(state):
    api, inbound = verify(state)
    link, client, q = checked_uri(api, state, inbound)
    result = Path(state['result_dir'])
    result.mkdir(mode=0o700, parents=True, exist_ok=True)
    panel = urllib.parse.urlsplit(state['panel_url'])
    remote_port = panel.port or (443 if panel.scheme == 'https' else 80)
    ssh_port = int(state.get('ssh_ports', [22])[0])
    tunnel_host = '[%s]' % panel.hostname if ':' in panel.hostname else panel.hostname
    tunnel = 'ssh -N -p %d -L 2053:%s:%d root@%s' % (
        ssh_port, tunnel_host, remote_port, state['domain'])
    browser_url = urllib.parse.urlunsplit((panel.scheme, '127.0.0.1:2053', panel.path, '', ''))
    secure_json(result / 'access.json', {
        'panel_url': state['panel_url'], 'username': state['panel_username'],
        'password': state['panel_password'], 'ssh_tunnel': tunnel,
        'browser_url': browser_url,
        'public_panel_enabled': None if state.get('is_existing') else False,
        'script_exposed_public_admin': False,
        'existing_panel': bool(state.get('is_existing'))})
    fd = os.open(result / 'client.txt', os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as f:
        f.write(link + '\n')
    os.chmod(result / 'client.txt', 0o600)
    config = {'log': {'loglevel': 'warning'}, 'inbounds': [{'listen': '127.0.0.1', 'port': 10888, 'protocol': 'socks', 'settings': {'auth': 'noauth', 'udp': True}}],
              'outbounds': [{'protocol': 'vless', 'settings': {'vnext': [{'address': state['domain'], 'port': 443, 'users': [{'id': client['id'], 'encryption': 'none', 'flow': q['flow'][0]}]}]},
              'streamSettings': {'network': 'tcp', 'security': 'reality', 'realitySettings': {'serverName': q['sni'][0], 'fingerprint': q['fp'][0], 'password': q['pbk'][0], 'shortId': q['sid'][0], 'spiderX': q.get('spx', ['/'])[0]}}}]}
    secure_json(result / 'client.json', config)
    secure_json(result / 'client-identity.json', {'inbound_id': inbound['id'], 'uuid': client['id'], 'uri_source': 'authenticated panel/api/inbounds/allLinks'})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['inspect', 'authenticate', 'bootstrap', 'configure', 'export', 'verify', 'rollback'])
    parser.add_argument('--state', required=True)
    args = parser.parse_args()
    os.umask(0o077)
    state = json.loads(Path(args.state).read_text())
    state.setdefault('panel_binary', '/usr/local/x-ui/x-ui')
    state.setdefault('panel_db', '/etc/x-ui/x-ui.db')
    state.setdefault('target_port', 9443)
    save = lambda: secure_json(args.state, state)
    try:
        if args.command == 'configure':
            configure(state, save)
        else:
            globals()[args.command](state)
        save()
    except Exception as exc:
        save()
        print('Panel helper: ' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
PANEL_PY
}
state_get() { python3 - "$STATE" "$1" <<'PY'
import json,sys
v=json.load(open(sys.argv[1])).get(sys.argv[2], '')
print(str(v).lower() if isinstance(v,bool) else v)
PY
}
helper() { python3 "$PANEL_HELPER" "$1" --state "$STATE"; }
snapshot() {
  local path=$1
  FILES+=("$path")
  if [[ -e $path || -L $path ]]; then
    mkdir -p "$BACKUP/files$(dirname "$path")"
    cp -a -- "$path" "$BACKUP/files$path"
  fi
}
cleanup() {
  local rc=$? path svc
  set +e
  trap - EXIT INT TERM
  [[ -z $SMOKE_PID ]] || { kill "$SMOKE_PID" 2>/dev/null || true; wait "$SMOKE_PID" 2>/dev/null || true; }
  if (( MUTATED && ! SUCCESS )); then
    echo 'Setup failed; restoring owned configuration and previous service states.' >&2
    helper rollback 2>/dev/null || echo 'Panel rollback needs inspection; retain private backup.' >&2
    [[ $(state_get is_existing) == true ]] || systemctl stop x-ui 2>/dev/null || true
    for path in "${FILES[@]}"; do
      rm -f -- "$path"
      if [[ -e $BACKUP/files$path || -L $BACKUP/files$path ]]; then cp -a -- "$BACKUP/files$path" "$path"; fi
    done
    if [[ $(state_get allow_firewall) == true ]] && command -v ufw >/dev/null; then
      if (( UFW_WAS_ACTIVE )); then ufw reload || true; else ufw --force disable || true; fi
    fi
    if (( FRESH_FILES )); then
      rm -rf /usr/local/x-ui
      # Fresh-only DB is retained privately for inspection, not left as a broken install.
      if [[ -d /etc/x-ui ]]; then mv /etc/x-ui "$BACKUP/failed-fresh-x-ui"; fi
    fi
    if (( FRESH_ROOT )); then rm -rf -- "$ROOT"; fi
    systemctl daemon-reload || true
    for svc in "${SERVICES[@]}"; do
      if [[ ${WAS_ENABLED[$svc]:-no} == yes ]]; then systemctl enable "$svc" 2>/dev/null || true; else systemctl disable "$svc" 2>/dev/null || true; fi
      if [[ ${WAS_ACTIVE[$svc]:-no} == yes ]]; then systemctl restart "$svc" 2>/dev/null || true; else systemctl stop "$svc" 2>/dev/null || true; fi
    done
    echo "Private backup: $BACKUP. Installed packages and issued certificates are retained." >&2
  fi
  rm -rf -- "$WORK"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ -z $DOMAIN ]]; then read -r -p 'Domain (fully qualified, no scheme): ' DOMAIN; fi
DOMAIN=${DOMAIN,,}
python3 - "$DOMAIN" <<'PY'
import re,sys
s=sys.argv[1]
if len(s)>253 or '.' not in s or not all(re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', x) for x in s.split('.')):
    sys.exit('Invalid DNS hostname. Use its ASCII/punycode form.')
PY
EMAIL=''
if (( ! CHECK )); then read -r -p 'Let’s Encrypt email (optional): ' EMAIL; fi
[[ -z $EMAIL || $EMAIL =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || fail 'Invalid email.'
DETECTED_SSH=$(python3 - <<'PY'
import re,subprocess
ports=set()
try:
 p=subprocess.run(['/usr/sbin/sshd','-T'],capture_output=True,text=True,check=True)
 ports.update(int(x) for x in re.findall(r'^port (\d+)$',p.stdout,re.M))
except (OSError,subprocess.CalledProcessError): pass
p=subprocess.run(['ss','-ltnpH'],capture_output=True,text=True,check=True)
for line in p.stdout.splitlines():
 if 'sshd' in line: ports.add(int(line.split()[3].rsplit(':',1)[1]))
print(' '.join(map(str,sorted(ports))))
PY
)
SSH_PORTS=''
if (( ! CHECK )); then read -r -p "SSH TCP ports [${DETECTED_SSH:-22}] (space separated): " SSH_PORTS; fi
SSH_PORTS=${SSH_PORTS:-${DETECTED_SSH:-22}}
PANEL_URL=''; PANEL_USER=''; PANEL_PASS=''; PANEL_2FA=''
if (( ! CHECK )) && [[ -e /etc/x-ui/x-ui.db ]]; then
  read -r -p 'Existing panel local URL/basePath (Enter to discover): ' PANEL_URL
  read -r -p 'Existing administrator login: ' PANEL_USER
  read -r -s -p 'Existing administrator password: ' PANEL_PASS; echo
  read -r -s -p 'Administrator two-factor code (optional): ' PANEL_2FA; echo
fi
SECURITY=n
if (( ! CHECK )); then
  read -r -p 'Manage firewall with UFW (deny incoming, allow outgoing) and enable SSH fail2ban? [Y/n]: ' SECURITY
  SECURITY=${SECURITY:-y}
  [[ ${SECURITY,,} == y || ${SECURITY,,} == n ]] || fail 'Answer y or n.'
  if [[ ${SECURITY,,} == n ]]; then echo 'WARNING: firewall/fail2ban setup skipped. External port restriction is NOT verified or enforced.' >&2; fi
fi
export DOMAIN EMAIL SSH_PORTS PANEL_URL PANEL_USER PANEL_PASS PANEL_2FA SECURITY
python3 - "$STATE" <<'PY'
import json,os,sys
ports=[int(p) for p in os.environ['SSH_PORTS'].split()]
if not ports or any(p<1 or p>65535 for p in ports): sys.exit('Invalid SSH ports')
s=dict(domain=os.environ['DOMAIN'],email=os.environ['EMAIL'],ssh_ports=sorted(set(ports)),panel_binary='/usr/local/x-ui/x-ui',panel_db='/etc/x-ui/x-ui.db',panel_url=os.environ['PANEL_URL'],panel_username=os.environ['PANEL_USER'],panel_password=os.environ['PANEL_PASS'],target_port=9443,allow_firewall=os.environ['SECURITY'].lower()=='y')
s['panel_two_factor_code']=os.environ['PANEL_2FA']
with open(sys.argv[1],'w') as f: json.dump(s,f)
os.chmod(sys.argv[1],0o600)
PY
unset PANEL_2FA
unset PANEL_PASS PANEL_USER
emit_panel_helper > "$PANEL_HELPER"
helper inspect
# Compare DNS to local addresses AND independent HTTPS public-IP detection.
DNS_RC=0
python3 - "$DOMAIN" <<'PY' || DNS_RC=$?
import ipaddress,json,socket,subprocess,sys,urllib.request
host=sys.argv[1]
try: dns={x[4][0] for x in socket.getaddrinfo(host,443,type=socket.SOCK_STREAM)}
except socket.gaierror as e: sys.exit(f'DNS lookup failed: {e}')
local=set()
p=subprocess.run(['ip','-j','address'],capture_output=True,text=True,check=True)
for interface in json.loads(p.stdout):
 for a in interface.get('addr_info',[]):
  if ipaddress.ip_address(a['local']).is_global: local.add(a['local'])
for url in ('https://api.ipify.org','https://api6.ipify.org'):
 try:
  value=urllib.request.urlopen(url,timeout=10).read(128).decode().strip()
  local.add(str(ipaddress.ip_address(value)))
 except Exception: pass
print('DNS A/AAAA:', ', '.join(sorted(dns)))
print('Detected public addresses:', ', '.join(sorted(local)) or '(unavailable)')
if not dns or not dns.issubset(local):
 print('Mismatch: fix every A/AAAA record (including stale IPv6). If behind NAT, explicit override requires checking port forwarding for TCP80/443.',file=sys.stderr)
 sys.exit(42)
PY
if (( DNS_RC )); then
  (( DNS_RC == 42 )) || fail 'DNS/public-address preflight failed.'
  (( ! CHECK )) || fail 'DNS mismatch: check is read-only and cannot approve a NAT override.'
  read -r -p 'NAT override: type I VERIFIED DNS AND PORT FORWARDING to continue: ' ANSWER
  [[ $ANSWER == 'I VERIFIED DNS AND PORT FORWARDING' ]] || fail 'DNS mismatch not approved.'
fi
SITE=/etc/nginx/sites-available/selfsteal-3xui-$DOMAIN
LINK=/etc/nginx/sites-enabled/selfsteal-3xui-$DOMAIN
ROOT=/var/www/selfsteal-3xui-$DOMAIN
EXISTING_SITE=''
STOCK_DEFAULT=0
if [[ -L /etc/nginx/sites-enabled/default ]] && [[ $(readlink -f /etc/nginx/sites-enabled/default) == /etc/nginx/sites-available/default ]]; then
  if python3 - <<'PY'
import hashlib,re,subprocess,sys
p='/etc/nginx/sites-available/default'
try:
 info=subprocess.check_output(['dpkg-query','-W','-f=${Conffiles}','nginx-common'],text=True)
 expected=next((m[1] for m in re.finditer(r'^\s*/etc/nginx/sites-available/default\s+([0-9a-f]{32})(?:\s|$)',info,re.M)),None)
 if expected and hashlib.md5(open(p,'rb').read()).hexdigest()==expected: sys.exit(0)
except (OSError,subprocess.CalledProcessError): pass
sys.exit(1)
PY
  then STOCK_DEFAULT=1; fi
fi
# Discover the actual config file rather than guessing or replacing a custom site.
if command -v nginx >/dev/null; then
  nginx -T > "$WORK/nginx.txt" 2>&1 || fail 'Existing nginx configuration is invalid.'
  EXISTING_SITE=$(python3 - "$WORK/nginx.txt" "$DOMAIN" "$STOCK_DEFAULT" <<'PY'
import re,sys
text=open(sys.argv[1]).read(); domain=sys.argv[2]; matches=[]; checked=[]
for path,body in re.findall(r'# configuration file ([^:\n]+):\n(.*?)(?=\n# configuration file |\Z)',text,re.S):
 if sys.argv[3]=='1' and path in ('/etc/nginx/sites-enabled/default','/etc/nginx/sites-available/default'): continue
 checked.append(body)
 if any(domain in names.split() for names in re.findall(r'\bserver_name\s+([^;]+);',body)):
  if not re.search(r'listen\s+127\.0\.0\.1:9443\s+ssl[^;]*proxy_protocol',body) or not re.search(r'ssl_protocols\s+TLSv1\.3\s*;',body) or 'ssl_reject_handshake on;' not in body or '/.well-known/acme-challenge/' not in body:
   sys.exit(f'Custom nginx site conflicts: {path}. Configure self-steal TLS1.3/PROXY listener and ACME explicitly; no file was replaced.')
  if f'/etc/letsencrypt/live/{domain}/fullchain.pem' not in body:
   sys.exit(f'Existing certificate configuration conflicts: {path}')
  matches.append(path)
if len(set(matches))>1: sys.exit('Multiple nginx files configure this domain; resolve conflict first.')
if matches: print(matches[0])
elif any(re.search(r'listen\s+(?:\[::\]:)?80[^;]*default_server',body) and not re.search(r'return\s+444\s*;',body) for body in checked):
 sys.exit('Existing default HTTP site does not reject unknown hosts. Preserve it or configure return444 manually before rerunning.')
PY
) || fail 'Nginx site conflict. Existing files were not changed.'
fi
python3 - "$EXISTING_SITE" <<'PY'
import subprocess,sys
for line in subprocess.check_output(['ss','-ltnpH'],text=True).splitlines():
 address=line.split()[3]; port=int(address.rsplit(':',1)[1])
 if port==80 and 'nginx' not in line: sys.exit('TCP80 is occupied by a non-nginx service.')
 if port==9443 and not (sys.argv[1] and 'nginx' in line and address.startswith('127.0.0.1:')):
  sys.exit('Target TCP9443 is occupied by an incompatible listener.')
PY
if [[ $(state_get allow_firewall) == true ]]; then
  # Do not fight another firewall manager or silently retain public panel rules.
  systemctl is-active --quiet firewalld && fail 'firewalld is active; use existing firewall management instead of UFW.' || true
  if command -v ufw >/dev/null; then
    python3 - <<'PY'
import pathlib,re,sys
p=pathlib.Path('/etc/default/ufw')
if not p.is_file(): sys.exit('UFW IPv6 policy file missing; inspect installation before opting into firewall management.')
s=p.read_text(); values=re.findall(r'^\s*IPV6\s*=\s*["\']?(yes|no)["\']?\s*(?:#.*)?$',s,re.M)
if len(values)!=1: sys.exit('UFW IPV6 setting is ambiguous; configure exactly one IPV6=yes/no assignment first.')
if values[0]=='no':
 rules=pathlib.Path('/etc/ufw/user6.rules')
 if rules.exists() and re.search(r'^-A ufw6-user-(?:input|forward)\b',rules.read_text(),re.M):
  sys.exit('UFW IPv6 is disabled with dormant custom IPv6 input/forward rules. Review/remove those rules before rerunning; switching IPv6 on could expose extra ports.')
 print('UFW IPv6 enforcement will be enabled; no dormant custom IPv6 inbound rules found.')
PY
    ufw status numbered > "$WORK/ufw.txt"
    python3 - "$WORK/ufw.txt" "$SSH_PORTS" <<'PY'
import re,sys
allowed={80,443,*map(int,sys.argv[2].split())}
for line in open(sys.argv[1]):
 if 'ALLOW' not in line and 'LIMIT' not in line: continue
 match=re.search(r'\]\s+(\d+)/tcp(?:\s|$)',line)
 if not match or int(match[1]) not in allowed:
  sys.exit('Existing UFW allow/limit rule is outside SSH/80/443. Review it manually; this script never resets firewall rules.')
PY
  fi
fi
if (( CHECK )); then echo 'Read-only preflight passed. No packages, releases, services or production files changed.'; exit 0; fi
printf '\nPlan: %s; self-steal443 ->127.0.0.1:9443; SSH ports:%s.\n' "$DOMAIN" "$SSH_PORTS"
echo 'Preserve existing identities/admin; new panel loopback only. Install dependencies, obtain real certificate, configure nginx and3x-ui.'
echo 'On failure owned files/service states are restored; packages/certificates remain.'
if (( STOCK_DEFAULT )); then echo 'Pristine distribution nginx default site will be disabled (backed up); custom sites remain untouched.'; fi
read -r -p 'Type APPLY to confirm all mutations: ' ANSWER
[[ $ANSWER == APPLY ]] || fail 'Cancelled without mutation.'
if [[ $(state_get is_existing) == true ]]; then helper authenticate; fi
STAMP=$(date -u +%Y%m%dT%H%M%SZ)-$$
BACKUP=/root/selfsteal-3xui/backups/$STAMP
RESULT=/root/selfsteal-3xui/results/$DOMAIN
mkdir -p "$BACKUP" "$RESULT"
chmod 700 /root/selfsteal-3xui "$BACKUP" "$RESULT"
python3 - "$STATE" "$BACKUP" "$RESULT" <<'PY'
import json,sys
p=sys.argv[1]; s=json.load(open(p)); s.update(backup_dir=sys.argv[2],result_dir=sys.argv[3]); json.dump(s,open(p,'w'))
PY
for svc in "${SERVICES[@]}"; do
  WAS_ACTIVE[$svc]=no; WAS_ENABLED[$svc]=no
  if systemctl is-active --quiet "$svc"; then WAS_ACTIVE[$svc]=yes; fi
  if systemctl is-enabled --quiet "$svc"; then WAS_ENABLED[$svc]=yes; fi
done
snapshot "$SITE"; snapshot "$LINK"
snapshot /etc/nginx/conf.d/selfsteal-3xui-default.conf
snapshot /etc/letsencrypt/renewal-hooks/deploy/selfsteal-3xui-nginx
snapshot /etc/fail2ban/jail.d/selfsteal-3xui.conf
snapshot /etc/systemd/system/x-ui.service
snapshot /etc/systemd/system/x-ui.service.d/selfsteal-permissions.conf
snapshot /usr/bin/x-ui
for path in /etc/ufw/user.rules /etc/ufw/user6.rules /etc/ufw/ufw.conf /etc/default/ufw; do snapshot "$path"; done
NGINX_WAS_INSTALLED=0
if command -v nginx >/dev/null; then NGINX_WAS_INSTALLED=1; fi
MUTATED=1
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl openssl nginx certbot qrencode iproute2 fail2ban ufw
if (( STOCK_DEFAULT || ! NGINX_WAS_INSTALLED )) && [[ -L /etc/nginx/sites-enabled/default && $(readlink -f /etc/nginx/sites-enabled/default) == /etc/nginx/sites-available/default ]]; then
  snapshot /etc/nginx/sites-enabled/default
  rm /etc/nginx/sites-enabled/default
fi
if [[ $(state_get is_existing) != true ]]; then
  case $(uname -m) in x86_64) ARCH=amd64;; aarch64|arm64) ARCH=arm64;; *) fail 'Fresh install supports amd64/arm64 only.';; esac
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    "https://api.github.com/repos/MHSanaei/3x-ui/releases/tags/v$VERSION" -o "$WORK/release.json"
  python3 - "$WORK/release.json" "$ARCH" "$WORK/release-meta" <<'PY'
import json,re,sys
r=json.load(open(sys.argv[1])); name=f'x-ui-linux-{sys.argv[2]}.tar.gz'
if r.get('tag_name')!='v3.8.5' or r.get('draft') or r.get('prerelease'): sys.exit('Invalid pinned release')
a=next((a for a in r['assets'] if a['name']==name),None)
if not a or not re.fullmatch(r'sha256:[0-9a-f]{64}',a.get('digest','')): sys.exit('Official API SHA256 digest unavailable; refusing execution')
url=a['browser_download_url']
if url!=f'https://github.com/MHSanaei/3x-ui/releases/download/v3.8.5/{name}': sys.exit('Unexpected asset origin')
open(sys.argv[3],'w').write(url+'\n'+a['digest'][7:]+'\n')
PY
  mapfile -t META < "$WORK/release-meta"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "${META[0]}" -o "$WORK/release.tar.gz"
  printf '%s  %s\n' "${META[1]}" "$WORK/release.tar.gz" | sha256sum --check --status || fail 'Release SHA256 mismatch.'
  # Validate all paths before extraction, including symlinks/hardlinks.
  python3 - "$WORK/release.tar.gz" <<'PY'
import pathlib,sys,tarfile
with tarfile.open(sys.argv[1]) as t:
 for m in t.getmembers():
  p=pathlib.PurePosixPath(m.name)
  if p.is_absolute() or '..' in p.parts or not p.parts or p.parts[0]!='x-ui' or m.issym() or m.islnk() or not (m.isfile() or m.isdir()): sys.exit('Unsafe release archive member')
PY
  [[ ! -e /usr/local/x-ui ]] || fail 'Existing /usr/local/x-ui without supported database: refusing overwrite.'
  [[ ! -e /etc/x-ui ]] || fail 'Fresh install has an existing /etc/x-ui directory; inspect manually before continuing.'
  FRESH_FILES=1
  tar -xzf "$WORK/release.tar.gz" -C /usr/local
  chmod 700 /usr/local/x-ui
  chmod 755 /usr/local/x-ui/x-ui /usr/local/x-ui/x-ui.sh /usr/local/x-ui/bin/xray-linux-"$ARCH"
  install -m 755 /usr/local/x-ui/x-ui.sh /usr/bin/x-ui
  SERVICE_SOURCE=/usr/local/x-ui/x-ui.service
  [[ -f $SERVICE_SOURCE ]] || SERVICE_SOURCE=/usr/local/x-ui/x-ui.service.debian
  [[ -f $SERVICE_SOURCE ]] || fail 'Verified archive contains no supported Debian service.'
  install -m 644 "$SERVICE_SOURCE" /etc/systemd/system/x-ui.service
  mkdir -p /etc/systemd/system/x-ui.service.d
  printf '[Service]\nUMask=0077\n' > /etc/systemd/system/x-ui.service.d/selfsteal-permissions.conf
  systemctl daemon-reload
  helper bootstrap
  systemctl enable --now x-ui
fi
# Existing compatible site is retained byte-for-byte, including public admin route.
if [[ -n $EXISTING_SITE ]]; then
  ROOT=$(python3 - "$EXISTING_SITE" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
m=re.search(r'location\s+(?:\^~\s+)?/\.well-known/acme-challenge/\s*\{[^}]*\broot\s+([^;]+);',s,re.S)
if not m: sys.exit('Cannot discover existing ACME webroot safely')
print(m[1].strip())
PY
)
else
  mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
  cat > "$SITE" <<NGINX_HTTP
# Managed by selfsteal-3xui; public panel is intentionally not proxied.
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    location ^~ /.well-known/acme-challenge/ { root $ROOT; }
    location / { return 301 https://\$host\$request_uri; }
}
NGINX_HTTP
  ln -s "$SITE" "$LINK"
  if ! nginx -T 2>&1 | python3 -c 'import re,sys; sys.exit(0 if re.search(r"listen\s+(?:\[::\]:)?80[^;]*default_server",sys.stdin.read()) else 1)'; then
    cat > /etc/nginx/conf.d/selfsteal-3xui-default.conf <<'NGINX_DEFAULT'
server { listen 80 default_server; listen [::]:80 default_server; server_name _; return 444; }
NGINX_DEFAULT
  fi
fi
if [[ -z $EXISTING_SITE ]]; then
  [[ ! -e $ROOT ]] || fail "Existing webroot $ROOT conflicts; no assets will be overwritten."
  FRESH_ROOT=1
  mkdir -p "$ROOT/.well-known/acme-challenge"
  chmod 755 "$ROOT" "$ROOT/.well-known" "$ROOT/.well-known/acme-challenge"
  printf '<!doctype html><title>Welcome</title><h1>Welcome</h1>\n' > "$ROOT/index.html"
  chmod 644 "$ROOT/index.html"
else
  [[ -d $ROOT/.well-known/acme-challenge ]] || fail 'Existing ACME webroot is absent; create it manually without changing site/asset permissions.'
fi
nginx -t
systemctl enable nginx
if systemctl is-active --quiet nginx; then systemctl reload nginx; else systemctl start nginx; fi
if [[ $(state_get allow_firewall) == true ]]; then
  # Preserve rule set; record complete UFW files for rollback of this transaction.
  python3 - <<'PY'
import pathlib,re,sys
p=pathlib.Path('/etc/default/ufw'); s=p.read_text()
pattern=r'^(\s*IPV6\s*=\s*)["\']?(?:yes|no)["\']?(\s*(?:#.*)?)$'
updated,n=re.subn(pattern,lambda m:m[1]+'yes'+m[2],s,flags=re.M)
if n!=1: sys.exit('Cannot safely enable UFW IPv6: ambiguous/missing IPV6 setting.')
if updated!=s: p.write_text(updated)
PY
  ufw default deny incoming
  ufw default allow outgoing
  for port in $SSH_PORTS; do ufw allow "$port/tcp"; done
  ufw allow 80/tcp; ufw allow 443/tcp
  ufw --force enable
fi
CERT_ARGS=(certonly --non-interactive --agree-tos --webroot -w "$ROOT" -d "$DOMAIN" --keep-until-expiring)
if [[ -n $EMAIL ]]; then CERT_ARGS+=(--email "$EMAIL"); else CERT_ARGS+=(--register-unsafely-without-email); fi
certbot "${CERT_ARGS[@]}"
if [[ -z $EXISTING_SITE ]]; then
  cat >> "$SITE" <<NGINX_TLS
server {
    listen 127.0.0.1:9443 ssl http2 proxy_protocol default_server;
    server_name _;
    ssl_protocols TLSv1.3;
    ssl_reject_handshake on;
}
server {
    listen 127.0.0.1:9443 ssl http2 proxy_protocol;
    server_name $DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.3;
    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;
    root $ROOT;
    location / { try_files \$uri \$uri/ =404; }
}
NGINX_TLS
fi
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
printf '#!/bin/sh\nset -eu\n/usr/sbin/nginx -t\n/bin/systemctl reload nginx\n' > /etc/letsencrypt/renewal-hooks/deploy/selfsteal-3xui-nginx
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/selfsteal-3xui-nginx
nginx -t
systemctl reload nginx
systemctl enable --now certbot.timer
if [[ $(state_get allow_firewall) == true ]]; then
  cat > /etc/fail2ban/jail.d/selfsteal-3xui.conf <<JAIL
[sshd]
enabled = true
backend = systemd
port = ${SSH_PORTS// /,}
JAIL
  fail2ban-client -t
  systemctl enable --now fail2ban
  systemctl restart fail2ban
fi
helper configure
helper verify
helper export
# The real exported client configuration is used, not a synthesized mock.
XRAY=''
for binary in /usr/local/x-ui/bin/xray-linux-*; do
  if [[ -f $binary && -x $binary ]]; then XRAY=$binary; break; fi
done
[[ -n $XRAY && -x $XRAY ]] || fail 'Bundled Xray executable missing.'
[[ -s $RESULT/client.json && -s $RESULT/client.txt ]] || fail 'Helper did not export actual client files.'
python3 - "$RESULT/client.json" "$WORK/smoke.json" <<'PY'
import json,socket,sys
c=json.load(open(sys.argv[1]))
sock=socket.socket(); sock.bind(('127.0.0.1',0)); port=sock.getsockname()[1]; sock.close()
c['inbounds']=[dict(listen='127.0.0.1',port=port,protocol='socks',settings={'auth':'noauth','udp':False})]
json.dump(c,open(sys.argv[2],'w')); print(port)
PY
SMOKE_PORT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["inbounds"][0]["port"])' "$WORK/smoke.json")
"$XRAY" run -c "$WORK/smoke.json" > "$WORK/smoke.log" 2>&1 &
SMOKE_PID=$!
for attempt in {1..30}; do
  if curl --fail --silent --show-error --max-time 10 --socks5-hostname "127.0.0.1:$SMOKE_PORT" https://api.ipify.org > "$RESULT/proxy-exit-ip.txt" 2>/dev/null; then break; fi
  kill -0 "$SMOKE_PID" 2>/dev/null || fail 'Real client Xray stopped; inspect private smoke log.'
  sleep 1
done
[[ -s $RESULT/proxy-exit-ip.txt ]] || fail 'Real client cannot reach HTTPS through Reality.'
curl --fail --silent --show-error --max-time 30 --socks5-hostname "127.0.0.1:$SMOKE_PORT" https://example.com/ -o "$WORK/proxy-https.html"
kill "$SMOKE_PID"; wait "$SMOKE_PID" || true; SMOKE_PID=''
curl --fail --silent --show-error --max-time 30 "https://$DOMAIN/" -o "$WORK/ordinary-https.html"
# Independent trusted TLS and strict wrong/no-SNI proof through the public endpoint.
python3 - "$DOMAIN" <<'PY'
import socket,ssl,sys
host=sys.argv[1]
ctx=ssl.create_default_context(); ctx.minimum_version=ssl.TLSVersion.TLSv1_3
with socket.create_connection((host,443),timeout=15) as s:
 with ctx.wrap_socket(s,server_hostname=host) as t:
  if t.version()!='TLSv1.3': sys.exit('Ordinary HTTPS did not negotiate TLS1.3')
  print('Trusted TLS1.3 and hostname certificate: verified')
for name in ('invalid.example',None):
 c=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT); c.check_hostname=False; c.verify_mode=ssl.CERT_NONE
 try:
  with socket.create_connection((host,443),timeout=15) as s:
   with c.wrap_socket(s,server_hostname=name): pass
 except ssl.SSLError: continue
 except OSError as e: sys.exit(f'Wrong/no-SNI verification inconclusive: {e}')
 sys.exit(f'Unexpected accepted TLS handshake for SNI {name!r}')
print('Wrong/no-SNI: rejected')
PY
helper verify
certbot renew --dry-run --run-deploy-hooks --cert-name "$DOMAIN"
qrencode -t UTF8 -o "$RESULT/client-qr.txt" < "$RESULT/client.txt"
cp "$STATE" "$BACKUP/final-state.json"; chmod 600 "$BACKUP/final-state.json"
chmod 600 "$RESULT"/*
echo "Setup verified. Private results: $RESULT; backup: $BACKUP"
echo "Real proxy exit IP: $(cat "$RESULT/proxy-exit-ip.txt")"
echo 'VLESS client URI (secret; do not post publicly):'
cat "$RESULT/client.txt"
cat "$RESULT/client-qr.txt"
echo "Panel access instructions/credentials: $RESULT/access.json (root-only)."
python3 - "$RESULT/access.json" <<'PY'
import json,sys
a=json.load(open(sys.argv[1]))
print('SSH tunnel:',a['ssh_tunnel'])
print('Open locally:',a['browser_url'])
PY
SUCCESS=1
