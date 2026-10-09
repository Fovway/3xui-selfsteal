#!/usr/bin/env bash
# Managed command: Fovway/3xui-selfsteal
# Interactive, fail-closed self-steal Reality setup; official 3x-ui v3.8.5.
set -Eeuo pipefail
umask 077
XUI_VERSION=3.8.5
SCRIPT_VERSION=2026.10.09.3
SCRIPT_COMMAND=/usr/local/bin/selfsteal
SCRIPT_BACKUP=/usr/local/share/selfsteal/previous.sh
SCRIPT_URL=https://raw.githubusercontent.com/Fovway/3xui-selfsteal/main/setup-selfsteal-3xui.sh
SCRIPT_MARKER='# Managed command: Fovway/3xui-selfsteal'
# Network checks must observe this machine, not an inherited proxy.
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY
CHECK=0
DOMAIN=''
ACTION='menu'
while (( $# )); do
  case $1 in
    --help|-h) cat <<'HELP'
Использование: sudo bash setup-selfsteal-3xui.sh [--install|--add-inbound|--parallel-reality|--recover-parallel|--repair-chain|--uninstall|--status|--check|--install-script|--update-script|--uninstall-script|--panel-access|--tests|--add-hysteria|--masking-audit]
Без аргументов открывается главное меню. При первом запуске меню устанавливается команда selfsteal.
--install-script устанавливает текущую копию скрипта как /usr/local/bin/selfsteal.
--update-script обновляет команду selfsteal из main на GitHub после проверки синтаксиса.
--uninstall-script удаляет только команду selfsteal, сохраняя настройку сервера.
--install запускает установку/настройку.
--add-inbound добавляет VLESS + Reality inbound, привязывает его к выбранному существующему пользователю и создаёт запись panel/hosts для сохранённого домена:443.
--repair-chain восстанавливает прежнюю последовательную Reality-цепочку (только для старого режима).
28 --parallel-reality преобразует имеющуюся Reality-цепочку в независимые inbound за nginx:443 по разным SNI с автоматическим откатом.
--uninstall удаляет только компоненты, созданные этим скриптом, и восстанавливает сохранённые конфигурации.
--status показывает состояние по пунктам без изменений.
--masking-audit проверяет маскировку Reality/TLS/HTTPS/Hysteria и закрытость панели, не изменяя конфигурацию.
--panel-access открывает переключатель публичного HTTPS-доступа к панели.
--add-hysteria добавляет Hysteria 2 на отдельном UDP-порту с TLS и Salamander, не меняя TCP Reality.
--tests открывает меню внешних тестов VPS.
--version показывает версию скрипта.
--check выполняет предварительную проверку системы, DNS и конфликтов без изменений и запроса учетных данных.
Недостающие утилиты предварительной проверки устанавливаются только после отдельного подтверждения.
При последующих ошибках эти пакеты сохраняются; --check ничего не устанавливает.
Администраторы и клиенты существующей 3x-ui сохраняются. Панель слушает только локальный адрес;
по умолчанию предлагается доступ к панели по HTTPS на введенном домене через секретный путь.
Закрытые результаты и резервные копии сохраняются в /root/selfsteal-3xui/.
HELP
      exit 0 ;;
    --version) printf 'selfsteal %s\n' "$SCRIPT_VERSION"; exit 0 ;;
    --check) CHECK=1; ACTION=preflight; shift ;;
    --uninstall-script) ACTION=uninstall-script; shift ;;
    --install-script) ACTION=install-script; shift ;;
    --update-script) ACTION=update-script; shift ;;
    --install) ACTION=install; shift ;;
    --add-inbound) ACTION=add-inbound; shift ;;
    --add-hysteria) ACTION=add-hysteria; shift ;;
    --repair-chain) ACTION=repair-chain; shift ;;
    --parallel-reality) ACTION=parallel-reality; shift ;;
    --recover-parallel) ACTION=recover-parallel; shift ;;
    --uninstall|--remove) ACTION=uninstall; shift ;;
    --panel-access) ACTION=panel-access; shift ;;
    --tests) ACTION=vps-tests; shift ;;
    --status) ACTION=status; shift ;;
    --masking-audit) ACTION=masking-audit; shift ;;
    --menu) ACTION=menu; shift ;;
    --domain) [[ $# -ge 2 ]] || { echo 'Не указан домен' >&2; exit 2; }; DOMAIN=$2; shift 2 ;;
    *) printf 'Неизвестный аргумент: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ -z $DOMAIN || $CHECK == 1 ]] || { echo '--domain поддерживается только вместе с --check' >&2; exit 2; }
fail() { printf 'ОШИБКА: %s\n' "$*" >&2; exit 1; }

# Management actions do not change the server installation or its state.
install_script_command() (
  local source=${1:-${BASH_SOURCE[0]}} temporary=''
  trap '[[ -z "$temporary" ]] || rm -f -- "$temporary"' EXIT
  [[ -f "$source" ]] || fail 'Не найден исходный файл скрипта.'
  grep -Fqx "$SCRIPT_MARKER" "$source" || fail 'Файл не является скриптом Fovway/3xui-selfsteal.'
  bash -n "$source" || fail 'Синтаксис скрипта некорректен; установленная команда сохранена.'
  [[ ! -L "$SCRIPT_COMMAND" ]] || fail "Команда $SCRIPT_COMMAND является ссылкой; замена отменена."
  if [[ -e "$SCRIPT_COMMAND" ]]; then
    [[ -f "$SCRIPT_COMMAND" ]] && grep -Fqx "$SCRIPT_MARKER" "$SCRIPT_COMMAND" || fail "Путь $SCRIPT_COMMAND занят другим файлом."
    if cmp -s "$source" "$SCRIPT_COMMAND"; then
      printf 'Команда selfsteal уже установлена: %s\n' "$SCRIPT_COMMAND"
      return 0
    fi
    install -d -m 700 "$(dirname "$SCRIPT_BACKUP")"
    install -m 600 "$SCRIPT_COMMAND" "$SCRIPT_BACKUP"
  fi
  install -d -m 755 "$(dirname "$SCRIPT_COMMAND")"
  temporary=$(mktemp "$(dirname "$SCRIPT_COMMAND")/.selfsteal.XXXXXXXX")
  install -m 755 "$source" "$temporary"
  mv -f -- "$temporary" "$SCRIPT_COMMAND"
  temporary=''
  printf 'Команда установлена: %s\nЗапуск меню: selfsteal (или sudo selfsteal).\n' "$SCRIPT_COMMAND"
)

update_script_command() (
  local download previous_version latest_version
  command -v curl >/dev/null || fail 'Для обновления требуется curl.'
  download=$(mktemp /tmp/selfsteal-update.XXXXXXXX)
  trap 'rm -f -- "$download"' EXIT
  previous_version=$(sed -n 's/^SCRIPT_VERSION=//p' "$SCRIPT_COMMAND" 2>/dev/null || true)
  echo 'Загрузка последней версии скрипта из GitHub...'
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --header 'Cache-Control: no-cache' "${SCRIPT_URL}?selfsteal_update=$(date +%s)-${RANDOM}" -o "$download" || fail 'Не удалось скачать обновление; установленная команда сохранена.'
  [[ -s "$download" ]] || fail 'GitHub вернул пустой файл; установленная команда сохранена.'
  install_script_command "$download"
  latest_version=$(sed -n 's/^SCRIPT_VERSION=//p' "$SCRIPT_COMMAND")
  printf 'Версия до обновления: %s\nУстановленная версия: %s\n' "${previous_version:-без номера}" "${latest_version:-без номера}"
  echo 'Для запуска установленной версии используйте /usr/local/bin/selfsteal.'
)

uninstall_script_command() {
  local answer
  [[ ! -L "$SCRIPT_COMMAND" ]] || fail "Команда $SCRIPT_COMMAND является ссылкой; удаление отменено."
  if [[ ! -e "$SCRIPT_COMMAND" ]]; then
    echo 'Команда selfsteal не установлена.'
    return 0
  fi
  [[ -f "$SCRIPT_COMMAND" ]] && grep -Fqx "$SCRIPT_MARKER" "$SCRIPT_COMMAND" || fail "Путь $SCRIPT_COMMAND занят другим файлом; удаление отменено."
  echo 'Будет удалена только команда selfsteal. Настройка сервера и резервные копии сохраняются.'
  read -r -p 'Для удаления команды введите REMOVE (иначе отмена): ' answer
  [[ "$answer" == REMOVE ]] || fail 'Удаление команды отменено.'
  rm -f -- "$SCRIPT_COMMAND"
  echo 'Команда selfsteal удалена. Для повторной установки скачайте скрипт с GitHub.'
}

ensure_screenshot_dependencies() {
  if python3 - <<'PY' >/dev/null 2>&1
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
assert Path('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf').exists()
PY
  then
    return 0
  fi

  command -v apt-get >/dev/null 2>&1 || {
    echo 'Не найден apt-get. Для PNG требуется Python Pillow.'
    return 1
  }

  echo 'Для создания PNG требуется пакет python3-pil. Устанавливаю...'
  DEBIAN_FRONTEND=noninteractive apt-get update || return 1
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3-pil fonts-dejavu-core || return 1
}

save_test_screenshot() {
  local title=$1 log_file=$2 safe_title stamp out_dir out_file host ip masked_ip
  ensure_screenshot_dependencies || {
    echo 'Не удалось установить зависимости для создания PNG.'
    return 1
  }

  out_dir=/root/selfsteal-3xui/test-screenshots
  install -d -m 700 "$out_dir"
  safe_title=$(printf '%s' "$title" | tr ' /:' '___' | tr -cd '[:alnum:]_.-')
  [[ -n "$safe_title" ]] || safe_title=test
  stamp=$(date '+%Y-%m-%d_%H-%M-%S')
  out_file="$out_dir/${stamp}_${safe_title}.png"
  host=$(hostname 2>/dev/null || printf 'VPS')
  ip=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -n1 || true)
  if [[ "$ip" =~ ^([0-9]+)\.([0-9]+)\.[0-9]+\.[0-9]+$ ]]; then
    masked_ip="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.*.*"
  else
    masked_ip='IP hidden'
  fi

  python3 - "$title" "$log_file" "$out_file" "$host" "$masked_ip" <<'PY'
import re
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

title, log_path, out_path, host, masked_ip = sys.argv[1:]
raw = Path(log_path).read_text(errors='replace')

# Убираем OSC-последовательности (например, терминальные гиперссылки).
raw = re.sub(r'\x1b\][^\x07]*(?:\x07|\x1b\\)', '', raw)
raw = raw.replace('\r\n', '\n')

# Терминальные progress-строки часто перерисовываются через CR.
# Для PNG оставляем только последнее состояние такой строки.
physical_lines = []
for part in raw.split('\n'):
    if '\r' in part:
        part = part.split('\r')[-1]
    physical_lines.append(part)

csi_re = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')

def visible_text(s):
    return csi_re.sub('', s)

# Убираем строки прогресса. В живом CLI они остаются, но в PNG не нужны.
filtered_lines = []
progress_patterns = [
    r'(?i)(?:^|\s)checking\s*:',
    r'(?i)^testing\s+.+\.\.\.',
    r'(?i)^checking\s+ip\s+database\b',
    r'(?i)^checking\s+stream\s+media\b',
    r'(?i)^checking\s+ai\s+provider\b',
    r'(?i)^connecting\s+email\s+server\b',
    r'(?i)^checking\s+blacklist\s+database\b',
]
for line in physical_lines:
    plain = visible_text(line).strip()
    if any(re.search(p, plain) for p in progress_patterns):
        continue
    filtered_lines.append(line)

def slice_from_last_marker(lines, patterns):
    for idx in range(len(lines) - 1, -1, -1):
        plain = visible_text(lines[idx]).strip()
        if any(re.search(p, plain, re.I) for p in patterns):
            return lines[idx:]
    return lines

title_l = title.lower()

# russian-iperf3-servers печатает красивую итоговую таблицу только после
# служебных spinner-строк. Для PNG оставляем именно этот финальный блок.
if 'iperf3' in title_l:
    filtered_lines = slice_from_last_marker(
        filtered_lines,
        [r'from the community, for the community', r'^server\s+download\s+upload\s+ping\b'],
    )

# Оба теста на базе xykt/IPQuality сначала рисуют баннеры и прогресс,
# а затем печатают готовый итоговый отчёт. Берём последний REPORT-блок.
if title == 'IPQuality' or 'блокировки зарубежными сервисами' in title_l:
    filtered_lines = slice_from_last_marker(
        filtered_lines,
        [r'ip\s+quality\s+check\s+report'],
    )

# Убираем остатки управляющих символов, которые не являются ANSI-цветами.
cleaned = []
for line in filtered_lines:
    line = line.replace('\b', '')
    line = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1a\x1c-\x1f\x7f]', '', line)
    cleaned.append(line)
filtered_lines = cleaned

# Убираем лишние пустые строки в начале/конце, но сохраняем разметку внутри.
while filtered_lines and not visible_text(filtered_lines[0]).strip():
    filtered_lines.pop(0)
while filtered_lines and not visible_text(filtered_lines[-1]).strip():
    filtered_lines.pop()

font_paths = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    '/usr/share/fonts/truetype/liberation2/LiberationMono-Regular.ttf',
]
bold_paths = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf',
    '/usr/share/fonts/truetype/liberation2/LiberationMono-Bold.ttf',
]

def pick(paths, size):
    for p in paths:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()

font = pick(font_paths, 24)
bold_font = pick(bold_paths, 24)
small = pick(font_paths, 19)
title_font = pick(bold_paths, 38)

DEFAULT = '#e5e7eb'
PALETTE = {
    30:'#64748b', 31:'#ef4444', 32:'#22c55e', 33:'#eab308',
    34:'#3b82f6', 35:'#d946ef', 36:'#06b6d4', 37:'#e5e7eb',
    90:'#94a3b8', 91:'#f87171', 92:'#4ade80', 93:'#facc15',
    94:'#60a5fa', 95:'#e879f9', 96:'#22d3ee', 97:'#f8fafc',
}

def xterm256(n):
    base = ['#000000','#800000','#008000','#808000','#000080','#800080','#008080','#c0c0c0',
            '#808080','#ff0000','#00ff00','#ffff00','#0000ff','#ff00ff','#00ffff','#ffffff']
    if 0 <= n < 16:
        return base[n]
    if 16 <= n <= 231:
        n -= 16
        r, g, b = n // 36, (n % 36) // 6, n % 6
        vals = [0, 95, 135, 175, 215, 255]
        return '#%02x%02x%02x' % (vals[r], vals[g], vals[b])
    if 232 <= n <= 255:
        v = 8 + (n - 232) * 10
        return '#%02x%02x%02x' % (v, v, v)
    return DEFAULT

def apply_sgr(params, color, is_bold):
    vals = []
    if not params:
        vals = [0]
    else:
        for x in params.replace(':', ';').split(';'):
            try:
                vals.append(int(x) if x else 0)
            except ValueError:
                pass
    i = 0
    while i < len(vals):
        code = vals[i]
        if code == 0:
            color, is_bold = DEFAULT, False
        elif code == 1:
            is_bold = True
        elif code == 22:
            is_bold = False
        elif code == 39:
            color = DEFAULT
        elif code in PALETTE:
            color = PALETTE[code]
        elif code == 38 and i + 1 < len(vals):
            if vals[i+1] == 5 and i + 2 < len(vals):
                color = xterm256(vals[i+2]); i += 2
            elif vals[i+1] == 2 and i + 4 < len(vals):
                r, g, b = vals[i+2:i+5]
                color = '#%02x%02x%02x' % (max(0,min(255,r)), max(0,min(255,g)), max(0,min(255,b)))
                i += 4
        i += 1
    return color, is_bold

def parse_ansi_line(line, state):
    color, is_bold = state
    chars = []
    pos = 0
    for m in csi_re.finditer(line):
        before = line[pos:m.start()]
        chars.extend((ch, color, is_bold) for ch in before)
        seq = m.group(0)
        if seq.endswith('m'):
            params = seq[2:-1]
            color, is_bold = apply_sgr(params, color, is_bold)
        pos = m.end()
    chars.extend((ch, color, is_bold) for ch in line[pos:])
    return chars, (color, is_bold)

max_chars = 112
render_lines = []
state = (DEFAULT, False)
for raw_line in filtered_lines:
    chars, state = parse_ansi_line(raw_line, state)
    if not chars:
        render_lines.append([])
        continue
    for i in range(0, len(chars), max_chars):
        render_lines.append(chars[i:i+max_chars])

if len(render_lines) > 220:
    render_lines = render_lines[:217] + [[], [(c, '#94a3b8', False) for c in '... output truncated in screenshot ...']]

probe = Image.new('RGB', (10, 10))
d = ImageDraw.Draw(probe)
line_h = int(d.textbbox((0, 0), 'Ag', font=font)[3] * 1.35)
header_h = 170
bottom_pad = 56
pad = 56
width = 1920
height = max(700, header_h + bottom_pad + max(1, len(render_lines)) * line_h)

img = Image.new('RGB', (width, height), '#0b1020')
d = ImageDraw.Draw(img)
d.rounded_rectangle((28, 28, width-28, height-28), radius=28, fill='#111827', outline='#334155', width=2)
d.text((pad, 55), title, font=title_font, fill='#f8fafc')
d.text((pad, 112), f'{host}  •  {masked_ip}', font=small, fill='#94a3b8')
d.line((pad, 154, width-pad, 154), fill='#334155', width=2)

def draw_run(draw, x, y, text, color, is_bold):
    if not text:
        return x
    f = bold_font if is_bold else font
    draw.text((x, y), text, font=f, fill=color or DEFAULT)
    return x + draw.textlength(text, font=f)

y = header_h
for line in render_lines:
    x = pad
    if not line:
        y += line_h
        continue
    run_text = ''
    run_color = None
    run_bold = None
    for ch, color, is_bold in line:
        if run_text and (color != run_color or is_bold != run_bold):
            x = draw_run(d, x, y, run_text, run_color, run_bold)
            run_text = ''
        if not run_text:
            run_color, run_bold = color, is_bold
        run_text += ch
    x = draw_run(d, x, y, run_text, run_color, run_bold)
    y += line_h

# Никакого брендинга self-steal/Fovway внизу изображения.
img.save(out_path, 'PNG', optimize=True)
PY

  chmod 600 "$out_file"
  printf 'PNG сохранён: %s\n' "$out_file"
}

after_test_menu() {
  local title=$1 log_file=$2 choice
  while :; do
    printf '\n1) Сохранить красивый PNG\n'
    printf '2) Вернуться к тестам\n'
    printf 'Выберите действие [1–2]: '
    read -r choice || choice=2
    case "$choice" in
      1) save_test_screenshot "$title" "$log_file" ;;
      2) rm -f -- "$log_file"; return 0 ;;
      *) echo 'Введите 1 или 2.' ;;
    esac
  done
}

VPS_TEST_STATUS_DIR=/root/selfsteal-3xui/test-status

save_vps_test_status() {
  local id=$1 rc=$2 status_file tmp
  install -d -m 700 "$VPS_TEST_STATUS_DIR"
  status_file="$VPS_TEST_STATUS_DIR/$id"
  tmp=$(mktemp "$VPS_TEST_STATUS_DIR/.status.XXXXXXXX")
  if (( rc == 0 )); then
    printf 'ok\n' > "$tmp"
  else
    printf 'fail\n' > "$tmp"
  fi
  chmod 600 "$tmp"
  mv -f -- "$tmp" "$status_file"
}

print_vps_test_item() {
  local id=$1 label=$2 amber=$3 green=$4 red=$5 reset=$6 status='' color=$amber
  if [[ -r "$VPS_TEST_STATUS_DIR/$id" ]]; then
    read -r status < "$VPS_TEST_STATUS_DIR/$id" || status=''
  fi
  case "$status" in
    ok) color=$green ;;
    fail) color=$red ;;
  esac
  printf '    %s%s)%s %s%s%s\n' "$color" "$id" "$reset" "$color" "$label" "$reset"
}

capture_test_command() {
  local command=$1 log_file=$2 quoted rc
  if command -v script >/dev/null 2>&1; then
    printf -v quoted '%q' "$command"
    TERM=xterm-256color script -qefc "bash -lc $quoted" /dev/null 2>&1 | tee "$log_file"
    rc=${PIPESTATUS[0]}
  else
    TERM=xterm-256color bash -lc "$command" 2>&1 | tee "$log_file"
    rc=${PIPESTATUS[0]}
  fi
  return "$rc"
}

run_vps_test() {
  local id=$1 title=$2 command=$3 rc=0 log_file
  log_file=$(mktemp /tmp/selfsteal-vps-test.XXXXXXXX.log)
  printf '\n────────────────────────────────────────────────────────────────\n'
  printf '  %s\n' "$title"
  printf '────────────────────────────────────────────────────────────────\n'
  printf 'Команда: %s\n\n' "$command"

  capture_test_command "$command" "$log_file" || rc=$?
  save_vps_test_status "$id" "$rc"

  printf '\n'
  if (( rc == 0 )); then
    echo 'Тест завершён.'
  else
    printf 'Тест завершился с кодом %d.\n' "$rc"
  fi
  after_test_menu "$title" "$log_file"
}

run_rkn_block_checker() {
  local venv=/tmp/selfsteal-rkn-checker-venv rc=0 log_file rkn_cmd=''
  log_file=$(mktemp /tmp/selfsteal-vps-test.XXXXXXXX.log)
  printf '\n────────────────────────────────────────────────────────────────\n'
  printf '  RKN Block Checker\n'
  printf '────────────────────────────────────────────────────────────────\n\n'

  if command -v rkn-check >/dev/null 2>&1; then
    rkn_cmd=$(command -v rkn-check)
  else
    if ! command -v python3 >/dev/null 2>&1; then
      echo 'Не найден python3.'
      rc=1
    fi
    if (( rc == 0 )); then
      rm -rf -- "$venv"
      if ! python3 -m venv "$venv" >/dev/null 2>&1; then
        echo 'Не удалось создать временное Python-окружение.'
        echo 'Установите пакет python3-venv и повторите тест.'
        rc=1
      elif "$venv/bin/python" -m pip install --quiet --disable-pip-version-check rkn-block-checker; then
        rkn_cmd="$venv/bin/rkn-check"
      else
        rc=$?
      fi
    fi
  fi

  if (( rc == 0 )); then
    capture_test_command "$rkn_cmd" "$log_file" || rc=$?
  else
    printf 'Не удалось подготовить RKN Block Checker.\n' > "$log_file"
  fi
  rm -rf -- "$venv"
  save_vps_test_status 9 "$rc"

  printf '\n'
  if (( rc == 0 )); then
    echo 'Тест завершён.'
  else
    printf 'Тест завершился с кодом %d.\n' "$rc"
  fi
  after_test_menu 'RKN Block Checker' "$log_file"
}

# Дополнительные тесты скорости: бинарники лежат отдельно от системных пакетов.
# Зафиксированные SHA-256 предотвращают запуск повреждённого архива.
prepare_speedtest_binary() {
  local tool=$1 arch url digest name target member temp archive
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) echo "Неподдерживаемая архитектура для $tool: $arch" >&2; return 1 ;;
  esac

  case "$tool:$arch" in
    ookla:amd64)
      url='https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz'
      digest='5690596c54ff9bed63fa3732f818a05dbc2db19ad36ed68f21ca5f64d5cfeeb7'
      name=speedtest ;;
    ookla:arm64)
      url='https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-aarch64.tgz'
      digest='3953d231da3783e2bf8904b6dd72767c5c6e533e163d3742fd0437affa431bd3'
      name=speedtest ;;
    librespeed:amd64)
      url='https://github.com/librespeed/speedtest-cli/releases/download/v1.0.14/librespeed-cli_1.0.14_linux_amd64.tar.gz'
      digest='89800767ac14085c78a20847ebea23340f6c14a78de0a15c2ac7db8b565c961f'
      name=librespeed-cli ;;
    librespeed:arm64)
      url='https://github.com/librespeed/speedtest-cli/releases/download/v1.0.14/librespeed-cli_1.0.14_linux_arm64.tar.gz'
      digest='75e51a2494d03cb35a92ddbf862b40571a25a1526f3cf3dfa8b1d5d7bc622bd9'
      name=librespeed-cli ;;
    *) echo "Нет сборки $tool для $arch" >&2; return 1 ;;
  esac

  # Используем подходящий установленный бинарник, не подменяя Python speedtest-cli.
  if [[ $tool == ookla ]] && command -v speedtest >/dev/null 2>&1 \
    && speedtest --version 2>&1 | grep -qi 'ookla'; then
    command -v speedtest
    return 0
  fi
  if [[ $tool == librespeed ]] && command -v librespeed-cli >/dev/null 2>&1; then
    command -v librespeed-cli
    return 0
  fi

  target="/root/selfsteal-3xui/tools/$name"
  if [[ -x "$target" ]]; then
    printf '%s\n' "$target"
    return 0
  fi

  for name in curl sha256sum tar install mktemp; do
    command -v "$name" >/dev/null 2>&1 || {
      echo "Для загрузки теста требуется утилита: $name" >&2
      return 1
    }
  done
  install -d -m 700 /root/selfsteal-3xui/tools || return 1
  temp=$(mktemp -d /tmp/selfsteal-speedtest.XXXXXXXX) || return 1
  archive="$temp/test.tar.gz"
  echo "Загрузка $tool с официального сайта..." >&2
  if ! curl -fSL --retry 2 --connect-timeout 15 --max-time 120 \
      --proto '=https' --tlsv1.2 "$url" -o "$archive"; then
    echo 'Скачать тест не удалось. Возможно, сайт недоступен с этого сервера.' >&2
    rm -rf -- "$temp"
    return 1
  fi
  if ! printf '%s  %s\n' "$digest" "$archive" | sha256sum -c - >/dev/null; then
    echo 'SHA-256 загруженного архива не совпадает. Выполнение отменено.' >&2
    rm -rf -- "$temp"
    return 1
  fi
  if [[ $tool == ookla ]]; then
    name=speedtest
  else
    name=librespeed-cli
  fi
  member=$(tar -tzf "$archive" | grep -E "(^|/)$name$" | head -n 1) || true
  if [[ -z "$member" || "$member" == /* || "$member" == *..* ]]; then
    echo "В архиве не найден исполняемый файл $name." >&2
    rm -rf -- "$temp"
    return 1
  fi
  if ! tar -xzf "$archive" -C "$temp" "$member" \
    || ! install -m 700 "$temp/$member" "$target"; then
    echo 'Не удалось распаковать тест скорости.' >&2
    rm -rf -- "$temp"
    return 1
  fi
  rm -rf -- "$temp"
  printf '%s\n' "$target"
}

run_speedtest_tool() {
  local id=$1 title=$2 tool=$3 args=$4 binary=''
  if binary=$(prepare_speedtest_binary "$tool"); then
    run_vps_test "$id" "$title" "$(printf '%q' "$binary") $args"
  else
    # Ошибка установки тоже сохраняется как красный статус теста.
    run_vps_test "$id" "$title" "echo 'Не удалось подготовить $title. Проверьте сообщение выше.' >&2; exit 1"
  fi
}

show_vps_tests_menu() {
  local choice cyan='' amber='' green='' red='' dim='' reset=''
  if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR+x} ]]; then
    cyan=$'\033[1;36m'; amber=$'\033[1;33m'; green=$'\033[1;32m'
    red=$'\033[1;31m'; dim=$'\033[90m'; reset=$'\033[0m'
  fi

  while :; do
    printf '\n%s  Тесты VPS%s\n' "$cyan" "$reset"
    printf '%s────────────────────────────────────────────────────────────────%s\n' "$dim" "$reset"
    print_vps_test_item 1 'IP region' "$amber" "$green" "$red" "$reset"
    print_vps_test_item 2 'Censorcheck — геоблок' "$amber" "$green" "$red" "$reset"
    print_vps_test_item 3 'Censorcheck — DPI для серверов РФ' "$amber" "$green" "$red" "$reset"
    print_vps_test_item 4 'Скорость до российских iPerf3 серверов' "$amber" "$green" "$red" "$reset"
    print_vps_test_item 5 'YABS' "$amber" "$green" "$red" "$reset"
    print_vps_test_item 6 'Блокировки зарубежными сервисами' "$amber" "$green" "$red" "$reset"
    print_vps_test_item 7 'Параметры сервера и зарубежные speedtest' "$amber" "$green" "$red" "$reset"
    print_vps_test_item 8 'IPQuality' "$amber" "$green" "$red" "$reset"
    print_vps_test_item 9 'RKN Block Checker' "$amber" "$green" "$red" "$reset"
    print_vps_test_item 10 'Speedtest (Ookla)' "$amber" "$green" "$red" "$reset"
    print_vps_test_item 11 'LibreSpeed (альтернативный замер)' "$amber" "$green" "$red" "$reset"
    printf '\n    0) Назад в главное меню\n\n'
    printf '%sВыберите тест [0–11]: %s' "$cyan" "$reset"
    read -r choice || return 0

    case "$choice" in
      1) run_vps_test 1 'IP region' 'bash <(wget -qO- https://ipregion.vrnt.xyz)' ;;
      2) run_vps_test 2 'Censorcheck — проверка геоблока' 'bash <(wget -qO- https://github.com/vernette/censorcheck/raw/master/censorcheck.sh) --mode geoblock' ;;
      3) run_vps_test 3 'Censorcheck — DPI для серверов РФ' 'bash <(wget -qO- https://github.com/vernette/censorcheck/raw/master/censorcheck.sh) --mode dpi' ;;
      4) run_vps_test 4 'Тест до российских iPerf3 серверов' 'bash <(wget -qO- https://github.com/itdoginfo/russian-iperf3-servers/raw/main/speedtest.sh)' ;;
      5) run_vps_test 5 'YABS' 'curl -sL yabs.sh | bash -s -- -4' ;;
      6) run_vps_test 6 'Проверка IP сервера на блокировки зарубежными сервисами' 'bash <(curl -Ls IP.Check.Place) -l en' ;;
      7) run_vps_test 7 'Параметры сервера и проверка скорости к зарубежным провайдерам' 'wget -qO- bench.sh | bash' ;;
      8) run_vps_test 8 'IPQuality' 'bash <(curl -Ls https://Check.Place) -EI' ;;
      9) run_rkn_block_checker ;;
      10) run_speedtest_tool 10 'Speedtest (Ookla)' ookla '' ;;
      11) run_speedtest_tool 11 'LibreSpeed' librespeed '--simple --telemetry-level disabled' ;;
      0) exec bash "${BASH_SOURCE[0]}" --menu ;;
      *) echo 'Введите число от 0 до 11.' ;;
    esac
  done
}

get_latest_github_script_version() {
  # Проверка не меняет систему и не блокирует вход в меню при сетевой ошибке.
  local latest=''
  command -v curl >/dev/null 2>&1 || return 0
  latest=$(curl --fail --silent --location \
    --connect-timeout 2 --max-time 6 --proto '=https' --tlsv1.2 \
    --header 'Cache-Control: no-cache' \
    "${SCRIPT_URL}?version_check=$(date +%s)" 2>/dev/null \
    | sed -n 's/^SCRIPT_VERSION=//p') || return 0
  latest=${latest%$'\r'}
  [[ "$latest" =~ ^[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}\.[0-9]+$ ]] || return 0
  printf '%s\n' "$latest"
}

github_version_is_newer() {
  local latest=$1
  [[ -n "$latest" && "$latest" != "$SCRIPT_VERSION" ]] || return 1
  # Ubuntu/Debian: sort -V сравнивает 2026.10.08.10 как более новую, чем .9.
  [[ "$(printf '%s\n%s\n' "$SCRIPT_VERSION" "$latest" | sort -V | tail -n 1)" == "$latest" ]]
}

menu_pause() {
  printf '\nНажмите Enter, чтобы вернуться в меню... '
  read -r _pause_answer || true
}

show_panel_address() {
  local state_file=''
  state_file=$(load_install_state || true)
  printf '\n  Адрес панели 3x-ui\n'
  printf '────────────────────────────────────────────────────────────────\n'
  if [[ -z "$state_file" || ! -r "$state_file" ]]; then
    echo 'Нет сохранённой конфигурации панели Self-Steal.'
    echo 'Если 3x-ui установлена отдельно, уточните адрес в настройках панели.'
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo 'Для чтения сохранённого адреса требуется python3.'
    return 0
  fi
  python3 - "$state_file" <<'PANEL_INFO_PY'
import json
import sys
try:
    with open(sys.argv[1], encoding='utf-8') as f:
        state = json.load(f)
except (OSError, ValueError) as exc:
    print('Не удалось прочитать настройки панели: ' + str(exc))
    sys.exit(0)
if state.get('removed'):
    print('Установка Self-Steal удалена. Сохранённый адрес может быть неактуален.')
    sys.exit(0)
local_url = state.get('panel_url') or ''
public_url = state.get('public_url') or ''
enabled = state.get('publish_panel') in (True, 'true')
print('  Локальный адрес:   ' + (local_url or 'не сохранён'))
if enabled and public_url:
    print('  Публичный адрес:  ' + public_url)
else:
    print('  Публичный доступ: выключен или не настроен')
print('  Локальный адрес доступен с сервера или через SSH-туннель.')
PANEL_INFO_PY
}

show_xui_status() {
  local state=''
  printf '\n  Состояние 3x-ui\n'
  printf '────────────────────────────────────────────────────────────────\n'
  if command -v systemctl >/dev/null 2>&1; then
    state=$(systemctl is-active x-ui 2>/dev/null || true)
    [[ -n "$state" ]] || state='не найден'
    case "$state" in
      active) echo '  Сервис x-ui:        работает' ;;
      inactive) echo '  Сервис x-ui:        остановлен' ;;
      failed) echo '  Сервис x-ui:        ошибка' ;;
      *) printf '  Сервис x-ui:        %s\n' "$state" ;;
    esac
  else
    echo '  Сервис x-ui:        systemctl недоступен'
  fi
  if [[ -x /usr/local/x-ui/x-ui ]]; then
    echo '  Файл 3x-ui:        найден'
  else
    echo '  Файл 3x-ui:        не найден'
  fi
  if [[ -s /etc/x-ui/x-ui.db ]]; then
    echo '  База данных:       найдена'
  else
    echo '  База данных:       не найдена'
  fi
  echo '  Проверка Reality и nginx: Self-Steal → Проверить конфигурацию.'
}

show_github_update_status() {
  local latest=''
  printf '\n  Проверка обновлений\n'
  printf '────────────────────────────────────────────────────────────────\n'
  printf '  Установленная версия: %s\n' "$SCRIPT_VERSION"
  latest=$(get_latest_github_script_version || true)
  if [[ -z "$latest" ]]; then
    echo '  GitHub недоступен. Повторите проверку позже.'
  elif github_version_is_newer "$latest"; then
    printf '  🔔 Новая версия на GitHub: %s\n' "$latest"
    echo '  Для обновления: пункт 2 этого раздела.'
  elif [[ "$latest" == "$SCRIPT_VERSION" ]]; then
    echo '  ✅ У вас актуальная версия.'
  else
    printf '  На GitHub: %s (не новее установленной)\n' "$latest"
  fi
}

masking_audit() {
  local state_file audit_dir report rc=0 choice
  command -v python3 >/dev/null 2>&1 || { echo 'Нужен установленный python3.'; return 1; }
  state_file=$(load_install_state || true)
  if [[ -z "$state_file" || ! -r "$state_file" ]]; then
    echo 'Нет сохранённого состояния Self-Steal. Сначала выполните установку.'
    return 1
  fi
  audit_dir=/root/selfsteal-3xui/audit
  install -d -m 700 "$audit_dir"
  report=$(mktemp "$audit_dir/audit-$(date +%Y%m%d-%H%M%S)-XXXXXXXX.txt") || return 1
  chmod 600 "$report"
  if python3 - "$state_file" <<'MASK_AUDIT_PY' | tee "$report"
import datetime
import ipaddress
import json
from pathlib import Path
import re
import socket
import sqlite3
import ssl
import subprocess
import sys
import urllib.parse

# Audit reads local configuration and makes a few bounded requests to the user's
# own loopback HTTPS endpoint. It never reads key contents or contacts scanners.
RESULTS = []


def emit(level, subject, message):
    safe = str(message).replace('\n', ' ').replace('\r', ' ')
    safe = re.sub(r'[\x00-\x1f\x7f]', '', safe)
    safe = safe[:200]
    RESULTS.append(level)
    print('[%-4s] %-28s %s' % (level, subject, safe))


def run_cmd(args, timeout=5):
    try:
        return subprocess.run(args, capture_output=True, text=True,
                              timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None


def load_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def local_tcp_address(listen):
    if not listen or listen in ('0.0.0.0', '::', '*'):
        return '127.0.0.1'
    try:
        ipaddress.ip_address(listen)
        return listen
    except ValueError:
        return None


def local_https_probe(ip, domain, hostname=None):
    context = ssl.create_default_context()
    context.set_alpn_protocols(['http/1.1'])
    # No DNS request to the domain: connect explicitly to the server's own IP.
    with socket.create_connection((ip, 443), timeout=4) as sock:
        sock.settimeout(4)
        with context.wrap_socket(sock, server_hostname=hostname or domain) as conn:
            tls = conn.version()
            alpn = conn.selected_alpn_protocol()
            conn.sendall(('HEAD / HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n'
                          % domain).encode('ascii'))
            raw = conn.recv(2048)
            first_line = raw.split(b'\r\n', 1)[0].decode('ascii', errors='replace')
            match = re.match(r'^HTTP/1\.[01] (\d{3})', first_line)
            return {'tls': tls, 'alpn': alpn,
                    'code': int(match.group(1)) if match else None}


def port_list(protocol):
    result = run_cmd(['ss', '-H', '-ln' + protocol])
    if result is None or result.returncode:
        return None
    matches = []
    for row in result.stdout.splitlines():
        tokens = row.split()
        # ss -H -ltn/-lun: local address is the fourth column (index 3).
        if len(tokens) < 5:
            continue
        addr = tokens[3]
        m = re.search(r':(\d+)$', addr)
        if m:
            matches.append(int(m.group(1)))
    return matches


def check_certificate(domain, cert_path):
    cert = Path(cert_path)
    if not cert.is_file():
        emit('FAIL', 'TLS-сертификат', 'Не найден fullchain.pem для домена')
        return
    check = run_cmd(['openssl', 'x509', '-in', str(cert), '-noout',
                     '-checkend', '604800'])
    if check is None:
        emit('WARN', 'TLS-сертификат', 'openssl недоступен; срок не проверен')
    elif check.returncode:
        emit('WARN', 'TLS-сертификат', 'Истекает менее чем через 7 дней или недействителен')
    else:
        emit('OK', 'TLS-сертификат', 'Не истечёт в ближайшие 7 дней')
    match = run_cmd(['openssl', 'x509', '-in', str(cert), '-noout',
                     '-checkhost', domain])
    if match is None:
        emit('WARN', 'Имя TLS-сертификата', 'Проверка недоступна')
    elif match.returncode == 0 and 'does match certificate' in match.stdout:
        emit('OK', 'Имя TLS-сертификата', 'Соответствует настроенному SNI')
    else:
        emit('FAIL', 'Имя TLS-сертификата', 'Не соответствует настроенному домену')


def inspect_database(state):
    db_path = Path(state.get('panel_db') or '/etc/x-ui/x-ui.db')
    if not db_path.is_file():
        emit('WARN', 'База 3x-ui', 'Нет локальной БД для проверки')
        return {}, []
    try:
        db_url = 'file:' + urllib.parse.quote(str(db_path)) + '?mode=ro'
        with sqlite3.connect(db_url, uri=True, timeout=3) as db:
            db.execute('PRAGMA query_only=ON')
            settings = dict(db.execute('SELECT key, value FROM settings'))
            db.row_factory = sqlite3.Row
            inbounds = [dict(r) for r in db.execute(
                'SELECT id, port, protocol, listen, stream_settings, tag '
                'FROM inbounds WHERE node_id IS NULL OR node_id=0')]
        emit('OK', 'База 3x-ui', 'Прочитана без изменений')
        return settings, inbounds
    except (sqlite3.Error, OSError, ValueError):
        emit('WARN', 'База 3x-ui', 'Не удалось прочитать настройки в режиме read-only')
        return {}, []


def inspect_panel(state, settings, tcp_ports):
    host = settings.get('webListen')
    panel_port = int(settings.get('webPort') or state.get('panel_port') or 2053)
    if host in ('127.0.0.1', '::1'):
        emit('OK', 'Админ-панель 3x-ui', 'Веб-интерфейс слушает только loopback')
    elif host is None:
        emit('WARN', 'Админ-панель 3x-ui', 'Адрес прослушивания неизвестен')
    else:
        emit('FAIL', 'Админ-панель 3x-ui', 'Веб-интерфейс не ограничен loopback')
    if tcp_ports is None:
        emit('WARN', 'Порт панели', 'Не удалось получить TCP-listeners')
    elif panel_port in tcp_ports and host not in ('127.0.0.1', '::1'):
        emit('WARN', 'Порт панели', 'Порт панели прослушивается вне loopback')
    elif panel_port in tcp_ports:
        emit('OK', 'Порт панели', 'Локальный listener обнаружен')
    else:
        emit('WARN', 'Порт панели', 'Указанный порт не найден среди listeners')
    if state.get('publish_panel'):
        emit('WARN', 'Публичный доступ', 'HTTPS-маршрут панели включён намеренно')
    else:
        emit('OK', 'Публичный доступ', 'По сохранённым настройкам публикация выключена')
    for key in ('subListen', 'subJsonListen', 'subClashListen'):
        if settings.get(key) and settings.get(key) not in ('127.0.0.1', '::1'):
            emit('WARN', 'Сервис подписок', 'Один из адресов подписок не loopback')
            break


def inspect_parallel_reality(state, inbounds, runtime, tcp_ports):
    records = [{'id': state.get('inbound_id'), 'port': state.get('primary_internal_port')}]
    records += [{'id': r.get('id'), 'port': r.get('port')} for r in state.get('added_inbounds') or []]
    mapping = state.get('parallel_sni_by_id') or {}
    seen = set()
    if len(records) != len(mapping):
        emit('FAIL', 'Reality SNI маршруты', 'Число записей маршрутизации не совпадает')
    by_id = {r.get('id'): r for r in inbounds}
    for rec in records:
        rid, port = rec['id'], rec['port']
        sni = mapping.get(str(rid))
        row = by_id.get(rid)
        label = 'Reality ID %s' % rid
        try:
            stream = json.loads(row.get('stream_settings') or '{}') if row else {}
            reality = stream.get('realitySettings') or {}
            good = (sni and sni not in seen and row.get('listen') == '127.0.0.1'
                    and row.get('protocol') == 'vless' and row.get('port') == port
                    and stream.get('security') == 'reality' and stream.get('network') in ('tcp', 'raw')
                    and reality.get('serverNames') == [sni]
                    and reality.get('target', reality.get('dest')) == '127.0.0.1:9443'
                    and reality.get('xver') == 1
                    and (stream.get('tcpSettings') or {}).get('acceptProxyProtocol') is True)
            if good:
                emit('OK', label, 'SNI %s; локальный TCP %s -> HTTPS fallback' % (sni, port))
                seen.add(sni)
            else:
                emit('FAIL', label, 'Конфигурация SNI, target, порта или loopback нарушена')
                continue
            live = [r for r in runtime if r.get('tag') == row.get('tag') and r.get('port') == port]
            if (len(live) == 1 and live[0].get('protocol') == 'vless'
                    and (live[0].get('streamSettings') or {}).get('realitySettings', {}).get('serverNames') == [sni]):
                emit('OK', 'Xray ' + label, 'Runtime SNI совпадает с панелью')
            else:
                emit('FAIL', 'Xray ' + label, 'Runtime не подтверждает inbound')
            if tcp_ports is not None and port not in tcp_ports:
                emit('FAIL', 'TCP ' + str(port), 'Внутренний порт Reality не прослушивается')
        except (ValueError, TypeError, AttributeError, KeyError):
            emit('FAIL', label, 'Невозможно прочитать параметры inbound')
    if tcp_ports is None or 443 not in tcp_ports:
        emit('FAIL', 'nginx TCP 443', 'Публичный TCP 443 не слушается')
    else:
        emit('OK', 'nginx TCP 443', 'Внешний общий TCP 443 прослушивается')
    try:
        stream_path = Path('/etc/nginx/modules-enabled/99-selfsteal-3xui-stream.conf')
        content = stream_path.read_text()
        routing_ok = (content.startswith('# Managed by selfsteal-3xui parallel;')
                      and all(('%s 127.0.0.1:%s;' % (mapping[str(r['id'])], r['port'])) in content
                              for r in records if str(r['id']) in mapping))
        emit('OK' if routing_ok else 'FAIL', 'nginx SNI map',
             'Все маршруты прописаны' if routing_ok else 'Файл маршрутизации изменён или неполон')
    except OSError:
        emit('FAIL', 'nginx SNI map', 'Управляемый stream-файл не найден')
    return '127.0.0.1'


def inspect_reality(state, inbounds, runtime, tcp_ports):
    if state.get('reality_mode') == 'parallel':
        return inspect_parallel_reality(state, inbounds, runtime, tcp_ports)
    matches = []
    for row in inbounds:
        if row.get('protocol') != 'vless' or row.get('port') != 443:
            continue
        try:
            stream = json.loads(row.get('stream_settings') or '{}')
        except (ValueError, TypeError):
            continue
        if stream.get('security') == 'reality' and stream.get('network') in ('tcp', 'raw'):
            matches.append((row, stream))
    if len(matches) != 1:
        emit('FAIL', 'Reality TCP 443', 'Ожидался ровно один VLESS/Reality inbound')
        return None
    row, stream = matches[0]
    emit('OK', 'Reality TCP 443', 'VLESS + Reality/TCP найден')
    reality = stream.get('realitySettings') or {}
    domain = state.get('domain', '')
    if reality.get('serverNames') == [domain]:
        emit('OK', 'Reality SNI', 'Совпадает с доменом установки')
    else:
        emit('FAIL', 'Reality SNI', 'Не соответствует домену установки')
    target = reality.get('target') or reality.get('dest') or ''
    target_match = re.fullmatch(r'127\.0\.0\.1:(\d+)', str(target))
    if target_match:
        emit('OK', 'Reality target', 'Переход на локальный HTTPS listener')
    else:
        emit('WARN', 'Reality target', 'Не указывает на 127.0.0.1:порт')
    live_rows = [r for r in runtime if r.get('tag') == row.get('tag')]
    if len(live_rows) == 1 and live_rows[0].get('protocol') == 'vless':
        live_reality = ((live_rows[0].get('streamSettings') or {}).get('realitySettings') or {})
        if (live_reality.get('serverNames') == reality.get('serverNames')
                and (live_reality.get('target') or live_reality.get('dest')) == target):
            emit('OK', 'Xray Reality runtime', 'SNI и target соответствуют базе')
        else:
            emit('FAIL', 'Xray Reality runtime', 'Рабочая конфигурация отличается от базы')
    else:
        emit('WARN', 'Xray Reality runtime', 'Inbound не подтверждён в config.json')
    if tcp_ports is None:
        emit('WARN', 'TCP 443 listener', 'Не удалось прочитать ss')
    elif 443 in tcp_ports:
        emit('OK', 'TCP 443 listener', 'Слушающий TCP-порт обнаружен')
    else:
        emit('FAIL', 'TCP 443 listener', 'TCP 443 не прослушивается')
    return local_tcp_address(row.get('listen'))


def inspect_hysteria(inbounds, runtime, udp_ports):
    entries = [r for r in inbounds if r.get('protocol') == 'hysteria']
    if not entries:
        emit('SKIP', 'Hysteria 2', 'Inbound этого типа отсутствуют')
        return
    for row in entries[:30]:
        port = row.get('port')
        label = 'Hysteria UDP %s' % port
        try:
            stream = json.loads(row.get('stream_settings') or '{}')
            hsettings = stream.get('hysteriaSettings') or {}
            tls = stream.get('tlsSettings') or {}
            certs = tls.get('certificates') or []
            masks = ((stream.get('finalmask') or {}).get('udp') or [])
            has_tls = (stream.get('security') == 'tls'
                       and stream.get('network') == 'hysteria'
                       and 'h3' in (tls.get('alpn') or [])
                       and any(Path(c.get('certificateFile') or '/missing-cert').is_file()
                               for c in certs))
            if hsettings.get('version') == 2 and has_tls:
                emit('OK', label, 'Hysteria 2, TLS, h3 и сертификат настроены')
            else:
                emit('FAIL', label, 'Некорректная версия, TLS/ALPN или сертификат')
            invalid = any(m.get('type') == 'salamander'
                          and not (m.get('settings') or {}).get('password') for m in masks)
            if invalid:
                emit('FAIL', 'Salamander UDP %s' % port, 'Не задан пароль маскировки')
            elif masks:
                emit('OK', 'Salamander UDP %s' % port, 'UDP-маскировка задана')
            else:
                emit('WARN', 'Salamander UDP %s' % port, 'Маскировка отключена')
            if udp_ports is None:
                emit('WARN', 'UDP listener %s' % port, 'ss недоступен')
            elif port in udp_ports:
                emit('OK', 'UDP listener %s' % port, 'UDP-порт прослушивается')
            else:
                emit('FAIL', 'UDP listener %s' % port, 'UDP-порт не прослушивается')
            running = [r for r in runtime if r.get('tag') == row.get('tag')
                       and r.get('protocol') == 'hysteria']
            if len(running) != 1:
                emit('WARN', 'Xray Hysteria %s' % port, 'Не подтверждён в runtime')
            else:
                emit('OK', 'Xray Hysteria %s' % port, 'Inbound присутствует в runtime')
        except (ValueError, TypeError, AttributeError, OSError):
            emit('WARN', label, 'Не удалось прочитать конфигурацию inbound')
    if len(entries) > 30:
        emit('WARN', 'Hysteria', 'Проверено только 30 из найденных inbound')


def run_audit(state):
    print('Аудит маскировки 3x-ui Self-Steal')
    print('Время UTC:', datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d %H:%M'))
    print('Проверяются только локальные настройки и собственный HTTPS listener.')
    print('Статусы отражают локальную конфигурацию, а не видимость для ТСПУ.')
    print('--------------------------------------------------------------')
    settings, inbounds = inspect_database(state)
    runtime = []
    runtime_file = Path(state.get('runtime_config')
                        or str(Path(state.get('panel_binary') or '/usr/local/x-ui/x-ui').parent
                               / 'bin/config.json'))
    try:
        runtime = (load_json(runtime_file).get('inbounds') or [])
        emit('OK', 'Xray runtime', 'Конфигурация прочитана')
    except (OSError, ValueError, TypeError, AttributeError):
        emit('WARN', 'Xray runtime', 'config.json недоступен')
    tcp_ports = port_list('t')
    udp_ports = port_list('u')
    inspect_panel(state, settings, tcp_ports)
    ip = inspect_reality(state, inbounds, runtime, tcp_ports)
    inspect_hysteria(inbounds, runtime, udp_ports)
    domain = state.get('domain') or ''
    if domain and re.fullmatch(r'[a-zA-Z0-9.-]+', domain):
        check_certificate(domain, '/etc/letsencrypt/live/' + domain + '/fullchain.pem')
    else:
        emit('WARN', 'Домен установки', 'Не указан или некорректен')
    if ip and domain:
        try:
            response = local_https_probe(ip, domain)
            if response['code'] is None:
                emit('WARN', 'HTTPS-заглушка', 'Нет HTTP-ответа на HEAD /')
            elif response['code'] in (200, 301, 302, 303, 307, 308, 403, 404, 405):
                emit('OK', 'HTTPS-заглушка', 'TLS %s, HTTP %s' % (
                    response['tls'], response['code']))
            else:
                emit('WARN', 'HTTPS-заглушка', 'HTTP %s, стоит проверить' % response['code'])
            if response['alpn'] == 'http/1.1':
                emit('OK', 'ALPN HTTPS', 'Согласован http/1.1')
            else:
                emit('WARN', 'ALPN HTTPS', 'ALPN отличается от http/1.1')
        except (OSError, ssl.SSLError, ValueError, UnicodeError):
            emit('WARN', 'HTTPS-заглушка', 'Локальное TLS-подключение не подтвердилось')
        try:
            # One benign invalid SNI handshake — it cannot simulate remote DPI.
            invalid = local_https_probe(ip, domain, hostname='invalid.example')
            emit('OK' if invalid.get('code') else 'WARN', 'Неизвестный SNI',
                 'Обычный HTTPS-ответ' if invalid.get('code') else 'Ответ без HTTP')
        except (OSError, ssl.SSLError, ValueError, UnicodeError):
            emit('WARN', 'Неизвестный SNI', 'TLS отклонён; внешнее поведение не определено')
    else:
        emit('SKIP', 'HTTPS-заглушка', 'Локальный адрес Reality не определён')
    if tcp_ports is not None and udp_ports is not None:
        expected = {22, 80, 443}
        unknown_tcp = sorted(set(tcp_ports) - expected)
        unknown_udp = sorted(set(udp_ports) - {443})
        emit('OK', 'TCP/UDP listeners', 'Инвентаризация выполнена (без проверки снаружи)')
        if unknown_tcp or unknown_udp:
            emit('WARN', 'Дополнительные порты',
                 '%s иных TCP и %s иных UDP портов; проверьте назначение' % (
                     len(unknown_tcp), len(unknown_udp)))
    firewall = run_cmd(['ufw', 'status'], timeout=4)
    if firewall is None:
        emit('WARN', 'UFW', 'Не найден; проверьте nftables и фаервол провайдера')
    elif 'Status: active' in firewall.stdout:
        emit('OK', 'UFW', 'Активен; правила и фаервол провайдера проверяйте отдельно')
    else:
        emit('WARN', 'UFW', 'Неактивен или статус неизвестен')
    print('--------------------------------------------------------------')
    print('Итого: OK=%d WARN=%d FAIL=%d SKIP=%d' % tuple(
        RESULTS.count(v) for v in ('OK', 'WARN', 'FAIL', 'SKIP')))
    print('Внешняя доступность из России и поведение ТСПУ здесь НЕ проверяются.')
    return 1 if 'FAIL' in RESULTS else 0


def main(argv):
    if len(argv) != 1:
        print('Нужен путь к state.json', file=sys.stderr)
        return 2
    try:
        state = load_json(argv[0])
    except (OSError, ValueError):
        print('Не удалось прочитать состояние Self-Steal.', file=sys.stderr)
        return 2
    if state.get('removed'):
        print('Установка помечена как удалённая.', file=sys.stderr)
        return 2
    try:
        return run_audit(state)
    except Exception:
        print('Аудит не завершился из-за ошибки чтения. Конфигурация не менялась.',
              file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

MASK_AUDIT_PY
  then
    rc=0
  else
    rc=1
  fi
  printf '\nОтчёт TXT (только root): %s\n' "$report"
  if [[ -t 0 ]]; then
    while :; do
      printf '\n1) Сохранить PNG\n0) Назад в меню\nВыберите действие [0–1]: '
      read -r choice || break
      case "$choice" in
        1)
          if python3 -c 'from PIL import Image, ImageDraw, ImageFont' >/dev/null 2>&1 && [[ -f /usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf ]]; then
            save_test_screenshot 'Аудит маскировки Self-Steal' "$report" || true
          else
            echo 'PNG пропущен: нужен python3-pil и шрифт DejaVu. Аудит не устанавливает пакеты.'
          fi
          ;;
        0) break ;;
        *) echo 'Введите 0 или 1.' ;;
      esac
    done
  fi
  return "$rc"
}

show_inbound_type_menu() {
  local choice
  while :; do
    printf '\n  ➕ Создать новый inbound\n'
    printf '────────────────────────────────────────────────────────────────\n'
    printf '    1) VLESS + Reality (TCP, существующая цепочка)\n'
    printf '    2) Hysteria 2 (UDP, TLS, Salamander)\n'
    printf '\n    0) ↩️ Назад\n\n'
    printf 'Выберите протокол [0–2]: '
    read -r choice || return 0
    case "$choice" in
      1) ACTION=add-inbound; return 0 ;;
      2) ACTION=add-hysteria; return 0 ;;
      0) return 0 ;;
      *) echo 'Введите 0, 1 или 2.' ;;
    esac
  done
}

show_submenu() {
  local section=$1 choice cyan='' green='' amber='' red='' dim='' reset=''
  while :; do
    case "$section" in
      xui)
        printf '\n%s  🖥️ Управление 3x-ui%s\n' "$green" "$reset"
        printf '%s────────────────────────────────────────────────────────────────%s\n' "$dim" "$reset"
        printf '    1) 🔗 Показать адрес панели управления\n'
        printf '    2) 🌐 Включить / выключить доступ к панели\n'
        printf '    3) ✅ Проверить состояние 3x-ui\n'
        printf '    4) 🛡️ Аудит маскировки сервера\n'
        printf '\n    0) ↩️ Назад в главное меню\n\n'
        printf '%sВыберите пункт [0–5]: %s' "$cyan" "$reset"
        ;;
      selfsteal)
        printf '\n%s  🌐 Настройка Self-Steal%s\n' "$cyan" "$reset"
        printf '%s────────────────────────────────────────────────────────────────%s\n' "$dim" "$reset"
        printf '    1) 🛠️ Установить\n'
        printf '    2) ➕ Создать новый inbound (VLESS / Hysteria 2)\n'
        printf '    3) 🔗 Исправить цепочку inbound\n'
        printf '    4) ✅ Проверить конфигурацию\n'
        printf '    5) 🔀 Независимые Reality через nginx / восстановление\n'
        printf '\n    0) ↩️ Назад в главное меню\n\n'
        printf '%sВыберите пункт [0–4]: %s' "$cyan" "$reset"
        ;;
      service)
        printf '\n%s  ⚙️ Обслуживание скрипта%s\n' "$amber" "$reset"
        printf '%s────────────────────────────────────────────────────────────────%s\n' "$dim" "$reset"
        printf '    1) 🔎 Проверить новую версию на GitHub\n'
        printf '    2) 🔄 Обновить скрипт\n'
        printf '\n    0) ↩️ Назад в главное меню\n\n'
        printf '%sВыберите пункт [0–2]: %s' "$cyan" "$reset"
        ;;
      removal)
        printf '\n%s  🗑️ Удаление%s\n' "$red" "$reset"
        printf '%s────────────────────────────────────────────────────────────────%s\n' "$dim" "$reset"
        printf '    1) 🗑️ Удалить всё, установленное скриптом\n'
        printf '    2) 🚮 Удалить скрипт и команду selfsteal\n'
        printf '\n    0) ↩️ Назад в главное меню\n\n'
        printf '%sВыберите пункт [0–2]: %s' "$cyan" "$reset"
        ;;
      *) echo 'Неизвестный раздел меню.'; return 1 ;;
    esac
    read -r choice || exit 0
    [[ "$choice" == 0 ]] && return 0
    case "$section:$choice" in
      xui:1) show_panel_address; menu_pause ;;
      xui:2) ACTION=panel-access; return 0 ;;
      xui:3) show_xui_status; menu_pause ;;
      xui:4) masking_audit || true; menu_pause ;;
      selfsteal:1) ACTION=install; return 0 ;;
      selfsteal:2) show_inbound_type_menu; [[ "$ACTION" == menu ]] || return 0 ;;
      selfsteal:3) ACTION=repair-chain; return 0 ;;
      selfsteal:4) ACTION=status; return 0 ;;
      selfsteal:5) ACTION=parallel-reality; return 0 ;;
      service:1) show_github_update_status; menu_pause ;;
      service:2) ACTION=update-script; return 0 ;;
      removal:1) ACTION=uninstall; return 0 ;;
      removal:2) ACTION=uninstall-script; return 0 ;;
      *) echo 'Такого пункта нет. Выберите номер из списка.' ;;
    esac
  done
}

show_menu() {
  local choice latest_version='' cyan='' green='' amber='' red='' dim='' reset=''
  if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR+x} ]]; then
    cyan=$'\033[1;36m'; green=$'\033[1;32m'; amber=$'\033[1;33m'
    red=$'\033[1;31m'; dim=$'\033[90m'; reset=$'\033[0m'
  fi
  latest_version=$(get_latest_github_script_version || true)
  while :; do
    printf '\n%s  3x-ui Self-Steal by Fovway%s\n' "$cyan" "$reset"
    printf '%s  Версия скрипта: %s%s\n' "$dim" "$SCRIPT_VERSION" "$reset"
    if github_version_is_newer "$latest_version"; then
      printf '\n%s  🔔 Доступна новая версия: %s (установлена: %s)%s\n' "$amber" "$latest_version" "$SCRIPT_VERSION" "$reset"
      printf '%s     Обновление: раздел 4 «Обслуживание скрипта», пункт 2.%s\n' "$amber" "$reset"
    fi
    printf '%s────────────────────────────────────────────────────────────────%s\n' "$dim" "$reset"
    printf '    %s1)%s 🖥️ Управление 3x-ui\n' "$green" "$reset"
    printf '    %s2)%s 🌐 Настройка Self-Steal\n' "$cyan" "$reset"
    printf '    %s3)%s 🧪 Тесты и диагностика VPS\n' "$amber" "$reset"
    printf '    %s4)%s ⚙️ Обслуживание скрипта\n' "$amber" "$reset"
    printf '    %s5)%s 🗑️ Удаление\n' "$red" "$reset"
    printf '%s────────────────────────────────────────────────────────────────%s\n' "$dim" "$reset"
    printf '    0) 🚪 Выход\n\n'
    printf '%sВыберите раздел [0–5]: %s' "$cyan" "$reset"
    read -r choice || exit 0
    case "$choice" in
      1) show_submenu xui ;;
      2) show_submenu selfsteal ;;
      3) ACTION=vps-tests ;;
      4) show_submenu service ;;
      5) show_submenu removal ;;
      0) exit 0 ;;
      *) echo 'Введите число от 0 до 5.' ;;
    esac
    if [[ "$ACTION" != menu ]]; then
      return 0
    fi
  done
}

load_install_state() {
  local candidate
  [[ -d /root/selfsteal-3xui ]] || return 1
  if [[ -f /root/selfsteal-3xui/state.json ]]; then
    printf '%s\n' /root/selfsteal-3xui/state.json
    return 0
  fi
  candidate=$(find /root/selfsteal-3xui/backups -mindepth 2 -maxdepth 2 -type f -name final-state.json -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1{sub(/^[^ ]+ /,""); print}')
  [[ -n "$candidate" ]] || return 1
  printf '%s\n' "$candidate"
}

status_mark() {
  case "$1" in
    ok) printf '[OK]' ;;
    warn) printf '[!!]' ;;
    fail) printf '[FAIL]' ;;
    skip) printf '[--]' ;;
  esac
}

status_line() {
  printf ' %s %-36s %s\n' "$(status_mark "$1")" "$2" "$3"
}

status_removed() {
  local state_file=$1 domain site snippet map_conf link root
  domain=$(python3 - "$state_file" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get('domain',''))
PY
)
  site=$(python3 - "$state_file" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); print(s.get('nginx_site') or ('/etc/nginx/sites-available/selfsteal-3xui-' + s.get('domain','')))
PY
)
  snippet=$(python3 - "$state_file" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); print(s.get('panel_snippet') or ('/etc/nginx/snippets/selfsteal-3xui-panel-' + s.get('domain','') + '.conf'))
PY
)
  map_conf=$(python3 - "$state_file" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); print(s.get('panel_map') or ('/etc/nginx/conf.d/selfsteal-3xui-panel-' + s.get('domain','') + '-map.conf'))
PY
)
  link="/etc/nginx/sites-enabled/$(basename "$site")"
  root="/var/www/selfsteal-3xui-$domain"
  status_line ok 'Self-steal установка' 'удалена'
  [[ -e /usr/local/x-ui || -e /etc/x-ui/x-ui.db ]] && status_line warn '3x-ui, установленная скриптом' 'остатки найдены' || status_line ok '3x-ui, установленная скриптом' 'не найдена'
  [[ -e "$site" || -L "$link" || -e "$snippet" || -e "$map_conf" || -e /etc/nginx/conf.d/selfsteal-3xui-default.conf ]] && status_line warn 'nginx-компоненты скрипта' 'остатки найдены' || status_line ok 'nginx-компоненты скрипта' 'не найдены'
  [[ -e "$root" ]] && status_line warn 'Страница-заглушка' "$root ещё существует" || status_line ok 'Страница-заглушка' 'удалена'
  echo
  echo 'Изменений не выполнено.'
  exit 0
}

status_report() {
  echo
  echo '==============================================='
  echo '       3xUI Self-Steal — проверка состояния'
  echo '==============================================='

  local state_file
  state_file=$(load_install_state || true)
  if [[ -z "$state_file" || ! -r "$state_file" ]]; then
    status_line warn 'Установка self-steal' 'сохранённого состояния нет'
    echo '  Скрипт не обнаружил свою установку.'
    exit 0
  fi
  command -v python3 >/dev/null || fail 'Для диагностики требуется python3.'

  local removed
  removed=$(python3 - "$state_file" <<'PY'
import json,sys
print(str(json.load(open(sys.argv[1])).get('removed',False)).lower())
PY
)
  [[ "$removed" == true ]] && status_removed "$state_file"

  local domain panel_port panel_path publish public_url result_dir allow_fw site snippet map_conf link certfile expiry reality_out installed_version
  domain=$(python3 - "$state_file" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get('domain',''))
PY
)
  panel_port=$(python3 - "$state_file" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get('panel_port','2053'))
PY
)
  panel_path=$(python3 - "$state_file" <<'PY'
import json,sys,urllib.parse
u=urllib.parse.urlsplit(json.load(open(sys.argv[1])).get('panel_url',''))
print(u.path or '/')
PY
)
  publish=$(python3 - "$state_file" <<'PY'
import json,sys
print(str(json.load(open(sys.argv[1])).get('publish_panel',False)).lower())
PY
)
  public_url=$(python3 - "$state_file" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get('public_url') or '')
PY
)
  result_dir=$(python3 - "$state_file" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get('result_dir') or '')
PY
)
  allow_fw=$(python3 - "$state_file" <<'PY'
import json,sys
print(str(json.load(open(sys.argv[1])).get('allow_firewall',False)).lower())
PY
)
  site=$(python3 - "$state_file" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); print(s.get('nginx_site') or ('/etc/nginx/sites-available/selfsteal-3xui-' + s.get('domain','')))
PY
)
  snippet=$(python3 - "$state_file" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); print(s.get('panel_snippet') or ('/etc/nginx/snippets/selfsteal-3xui-panel-' + s.get('domain','') + '.conf'))
PY
)
  map_conf=$(python3 - "$state_file" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); print(s.get('panel_map') or ('/etc/nginx/conf.d/selfsteal-3xui-panel-' + s.get('domain','') + '-map.conf'))
PY
)
  link="/etc/nginx/sites-enabled/$(basename "$site")"

  status_line ok 'Сохранённое состояние' "$state_file"
  status_line ok 'Домен' "$domain"

  if [[ -x /usr/local/x-ui/x-ui ]]; then
    installed_version=$(/usr/local/x-ui/x-ui -v 2>/dev/null | sed 's/^v//' || true)
    if [[ "$installed_version" == '3.8.5' ]]; then
      status_line ok '3x-ui версия' "$installed_version"
    elif [[ -n "$installed_version" ]]; then
      status_line warn '3x-ui версия' "$installed_version (проверена 3.8.5)"
    else
      status_line warn '3x-ui версия' 'не удалось определить'
    fi
    systemctl is-active --quiet x-ui && status_line ok '3x-ui сервис' 'запущен' || status_line fail '3x-ui сервис' 'не запущен'
    systemctl is-enabled --quiet x-ui >/dev/null 2>&1 && status_line ok '3x-ui автозапуск' 'включён' || status_line warn '3x-ui автозапуск' 'выключен'
    if ss -H -ltn 2>/dev/null | grep -Eq "127\\.0\\.0\\.1:$panel_port[[:space:]]"; then
      status_line ok 'Панель слушает' "127.0.0.1:$panel_port"
    else
      status_line warn 'Панель слушает' "127.0.0.1:$panel_port не найден"
    fi
    [[ -f /etc/x-ui/x-ui.db ]] && status_line ok 'База 3x-ui' '/etc/x-ui/x-ui.db' || status_line fail 'База 3x-ui' 'файл базы не найден'
    status_line ok 'Локальный basePath' "$panel_path"
  else
    status_line fail '3x-ui' 'исполняемый файл не найден'
  fi

  if [[ -f /etc/x-ui/x-ui.db ]]; then
    reality_out=$(python3 - "$state_file" <<'PY'
import sqlite3,json,sys
try:
    db=sqlite3.connect('file:/etc/x-ui/x-ui.db?mode=ro', uri=True)
    rows=db.execute('SELECT id,protocol,port,stream_settings FROM inbounds WHERE port=443 AND (node_id IS NULL OR node_id=0)').fetchall()
    rows=[row for row in rows if row[1] not in ('hysteria','tuic','wireguard','amneziawg')
          and json.loads(row[3] or '{}').get('network') not in ('hysteria','kcp','quic')]
    if not rows:
        print('WARN|Reality inbound|на локальном порту 443 не найден')
    elif len(rows)>1:
        print('WARN|Reality inbound|найдено несколько входящих на 443')
    else:
        rid,proto,port,stream=rows[0]
        stream=json.loads(stream); reality=stream.get('realitySettings') or {}
        good=(proto=='vless' and stream.get('security')=='reality' and stream.get('network') in ('tcp','raw'))
        target=reality.get('target') or reality.get('dest')
        sni=",".join(reality.get('serverNames') or []) or 'не задан'
        if good:
            print('OK|Reality inbound|id=%s, port=443, target=%s, SNI=%s' % (rid,target or 'не задан',sni))
            state=json.load(open(sys.argv[1]))
            added=state.get('added_inbounds') or []
            expected_port=added[0]['port'] if state.get('reality_chain') and added else state.get('target_port',9443)
            if target and target != '127.0.0.1:%d' % expected_port:
                print('WARN|Reality target|' + target)
        else:
            print('FAIL|Reality inbound|порт 443 найден, но это не VLESS + Reality/TCP')
except Exception as e:
    print('FAIL|Reality inbound|ошибка чтения базы: ' + str(e))
PY
)
    while IFS='|' read -r level name detail; do
      case "$level" in
        OK) status_line ok "$name" "$detail" ;;
        WARN) status_line warn "$name" "$detail" ;;
        FAIL) status_line fail "$name" "$detail" ;;
      esac
    done <<< "$reality_out"
  fi

  if command -v nginx >/dev/null; then
    systemctl is-active --quiet nginx && status_line ok 'nginx сервис' 'запущен' || status_line fail 'nginx сервис' 'не запущен'
    nginx -t >/dev/null 2>&1 && status_line ok 'nginx конфигурация' 'корректна' || status_line fail 'nginx конфигурация' 'ошибка nginx -t'
    [[ -f "$site" ]] && status_line ok 'nginx сайт' "$site" || status_line warn 'nginx сайт' 'управляемый сайт не найден'
    [[ -L "$link" ]] && status_line ok 'nginx site-link' "$link" || status_line warn 'nginx site-link' 'ссылка не найдена'
    [[ -f "$snippet" ]] && status_line ok 'Маршрут панели' "$snippet" || { [[ "$publish" == false ]] && status_line skip 'Маршрут панели' 'публикация выключена' || status_line fail 'Маршрут панели' 'include не найден'; }
    [[ -f "$map_conf" ]] && status_line ok 'WebSocket map' "$map_conf" || status_line warn 'WebSocket map' 'файл не найден'
  else
    status_line fail 'nginx' 'не установлен'
  fi

  certfile="/etc/letsencrypt/live/$domain/fullchain.pem"
  if [[ -s "$certfile" ]]; then
    expiry=$(openssl x509 -enddate -noout -in "$certfile" 2>/dev/null | cut -d= -f2- || true)
    if [[ -n "$expiry" ]]; then
      status_line ok 'TLS сертификат' "до $expiry"
    else
      status_line warn 'TLS сертификат' 'найден, срок не удалось определить'
    fi
  else
    status_line fail 'TLS сертификат' "не найден для $domain"
  fi
  systemctl is-active --quiet certbot.timer && status_line ok 'certbot timer' 'запущен' || status_line warn 'certbot timer' 'не запущен'

  if [[ "$allow_fw" == true ]]; then
    if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
      status_line ok 'UFW' 'активен'
      ufw status | grep -Eq '443/tcp.*ALLOW|80/tcp.*ALLOW' && status_line ok 'UFW веб-порты' '80/443 разрешены' || status_line warn 'UFW веб-порты' 'ожидаемые правила не найдены'
    else
      status_line fail 'UFW' 'не активен, хотя его включали при установке'
    fi
    systemctl is-active --quiet fail2ban && status_line ok 'fail2ban' 'запущен' || status_line warn 'fail2ban' 'не запущен'
    [[ -f /etc/fail2ban/jail.d/selfsteal-3xui.conf ]] && status_line ok 'fail2ban SSH-jail' 'файл найден' || status_line warn 'fail2ban SSH-jail' 'файл не найден'
  else
    status_line skip 'UFW / fail2ban' 'не включались этим скриптом'
  fi

  if [[ "$publish" == true ]]; then
    [[ -n "$public_url" ]] && status_line ok 'Публичная панель' "$public_url" || status_line warn 'Публичная панель' 'URL не сохранён'
  else
    status_line skip 'Публичная панель' 'отключена'
  fi

  if getent ahosts "$domain" >/dev/null 2>&1; then
    status_line ok 'DNS' 'домен резолвится'
  else
    status_line fail 'DNS' "домен $domain не резолвится"
  fi

  if [[ -n "$result_dir" && -s "$result_dir/client.txt" ]]; then
    status_line ok 'Конфигурация клиента' "$result_dir/client.txt"
    if [[ -s "$result_dir/proxy-exit-ip.txt" ]]; then
      status_line ok 'Тест Reality' "выходной IP: $(cat "$result_dir/proxy-exit-ip.txt")"
    else
      status_line warn 'Тест Reality' 'результат smoke-test не найден'
    fi
  else
    status_line warn 'Результаты установки' 'client.txt не найден'
  fi

  echo
  echo 'Итог:'
  if curl -fsS --max-time 8 "https://$domain/" >/dev/null 2>&1; then
    echo '  [OK] Обычный HTTPS-сайт отвечает.'
  else
    echo '  [!!] Обычный HTTPS-сайт не ответил на проверку.'
  fi
  echo '  Проверка ничего не изменяет и не перезапускает сервисы.'
  echo
  exit 0
}

uninstall_script() {
  echo
  echo '==============================================='
  echo '        3xUI Self-Steal — удаление'
  echo '==============================================='

  local state_file nginx_reload_status='not-active'
  state_file=$(load_install_state || true)
  [[ -n "$state_file" && -r "$state_file" ]] || fail 'Не найдено сохранённое состояние установки. Нужен state.json или final-state.json из резервной копии.'
  command -v python3 >/dev/null || fail 'Для удаления требуется python3.'

  local domain backup_dir is_existing cert_was_present fresh_root site snippet map_conf
  domain=$(python3 - "$state_file" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get('domain',''))
PY
)
  backup_dir=$(python3 - "$state_file" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get('backup_dir',''))
PY
)
  is_existing=$(python3 - "$state_file" <<'PY'
import json,sys
print(str(json.load(open(sys.argv[1])).get('is_existing',False)).lower())
PY
)
  cert_was_present=$(python3 - "$state_file" <<'PY'
import json,sys
print(str(json.load(open(sys.argv[1])).get('cert_was_present',True)).lower())
PY
)
  fresh_root=$(python3 - "$state_file" <<'PY'
import json,pathlib,sys
state=json.load(open(sys.argv[1]))
owned=state.get('fresh_root')
if owned is None:
    # Older successful installs did not persist fresh_root. Infer ownership only
    # when this script's nginx site was absent from that install's pre-change backup.
    domain=state.get('domain','')
    expected=f'/etc/nginx/sites-available/selfsteal-3xui-{domain}' if domain else ''
    site=state.get('nginx_site','')
    backup_value=state.get('backup_dir')
    backup=pathlib.Path(backup_value) if backup_value else None
    relative=pathlib.Path(expected.lstrip('/')) if expected else pathlib.Path('/')
    prior_site=backup/'files'/relative if backup and expected else pathlib.Path('/nonexistent')
    owned=bool(expected and site == expected and backup and backup.is_dir() and not (prior_site.exists() or prior_site.is_symlink()))
print(str(bool(owned)).lower())
PY
)
  site=$(python3 - "$state_file" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); print(s.get('nginx_site') or ('/etc/nginx/sites-available/selfsteal-3xui-' + s.get('domain','')))
PY
)
  snippet=$(python3 - "$state_file" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); print(s.get('panel_snippet') or ('/etc/nginx/snippets/selfsteal-3xui-panel-' + s.get('domain','') + '.conf'))
PY
)
  map_conf=$(python3 - "$state_file" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); print(s.get('panel_map') or ('/etc/nginx/conf.d/selfsteal-3xui-panel-' + s.get('domain','') + '-map.conf'))
PY
)

  echo
  echo "Домен: $domain"
  echo "Резервная копия: $backup_dir"
  echo
  if [[ "$is_existing" == true ]]; then
    echo 'ВНИМАНИЕ: 3x-ui существовала до установки этого скрипта.'
    echo 'Для удаления изменений self-steal база 3x-ui будет восстановлена'
    echo 'из panel-before.db. Изменения в 3x-ui, сделанные после установки скрипта,'
    echo 'могут быть потеряны.'
  else
    echo '3x-ui была установлена этим скриптом и будет удалена.'
  fi
  read -r -p 'Для подтверждения удаления введите REMOVE: ' ANSWER
  [[ "$ANSWER" == 'REMOVE' ]] || fail 'Удаление отменено.'

  if [[ "$is_existing" == true ]]; then
    systemctl stop x-ui 2>/dev/null || true
    if [[ -s "$backup_dir/panel-before.db" ]]; then
      [[ -d /etc/x-ui ]] || mkdir -p /etc/x-ui
      cp -a "$backup_dir/panel-before.db" /etc/x-ui/x-ui.db
      chmod 600 /etc/x-ui/x-ui.db
    fi
  else
    systemctl disable --now x-ui 2>/dev/null || true
  fi

  python3 - "$backup_dir" "$site" "$snippet" "$map_conf" "$domain" "$fresh_root" <<'PY'
import os,pathlib,shutil,sys
backup=pathlib.Path(sys.argv[1])
site=pathlib.Path(sys.argv[2])
snippet=pathlib.Path(sys.argv[3])
map_conf=pathlib.Path(sys.argv[4])
domain=sys.argv[5]
fresh_root=sys.argv[6].lower()=='true'
root=pathlib.Path('/var/www/selfsteal-3xui-'+domain) if domain else None
managed=[
    site,
    pathlib.Path('/etc/nginx/sites-enabled/selfsteal-3xui-'+domain) if domain else None,
    snippet,
    map_conf,
    pathlib.Path('/etc/nginx/conf.d/selfsteal-3xui-default.conf'),
    pathlib.Path('/etc/nginx/modules-enabled/99-selfsteal-3xui-stream.conf'),
    pathlib.Path('/etc/nginx/conf.d/99-selfsteal-3xui-parallel-tls.conf'),
    pathlib.Path('/etc/nginx/sites-enabled/99-selfsteal-3xui-parallel-acme.conf'),
    pathlib.Path('/etc/letsencrypt/renewal-hooks/deploy/selfsteal-3xui-nginx'),
    pathlib.Path('/etc/fail2ban/jail.d/selfsteal-3xui.conf'),
    pathlib.Path('/etc/systemd/system/x-ui.service'),
    pathlib.Path('/etc/systemd/system/x-ui.service.d/selfsteal-permissions.conf'),
    pathlib.Path('/usr/bin/x-ui'),
]
def rm_item(p):
    if not p: return
    try:
        if p.is_symlink() or p.is_file(): p.unlink()
        elif p.is_dir(): shutil.rmtree(p)
    except FileNotFoundError:
        pass
def copy_item(src,dst):
    rm_item(dst)
    dst.parent.mkdir(mode=0o755,parents=True,exist_ok=True)
    if src.is_symlink():
        dst.symlink_to(os.readlink(src))
    elif src.is_dir():
        shutil.copytree(src,dst,symlinks=True)
    else:
        shutil.copy2(src,dst,follow_symlinks=False)
snap=backup/'files'
if snap.is_dir():
    for src in sorted(snap.rglob('*')):
        if src.is_dir() and not src.is_symlink():
            continue
        copy_item(src,pathlib.Path('/')/src.relative_to(snap))
for p in managed:
    if p is None: continue
    relative=pathlib.Path(str(p).lstrip('/'))
    if not (snap/relative).exists() and not (snap/relative).is_symlink():
        rm_item(p)
if fresh_root and root:
    rm_item(root)
PY

  if [[ "$is_existing" != true ]]; then
    rm -rf /usr/local/x-ui /etc/x-ui /etc/systemd/system/x-ui.service.d
    rm -f /usr/bin/x-ui /etc/systemd/system/x-ui.service
  fi
  systemctl daemon-reload

  if [[ "$cert_was_present" == false && -n "$domain" && -x /usr/bin/certbot ]]; then
    if certbot certificates 2>/dev/null | grep -Fq "Certificate Name: $domain"; then
      certbot delete --cert-name "$domain" --non-interactive || true
    fi
  fi

  local packages
  packages=$(python3 - "$state_file" <<'PY'
import json,sys
for p in json.load(open(sys.argv[1])).get('packages_added_by_script',[]):
    print(p)
PY
)
  if [[ -n "$packages" ]]; then
    echo 'Удаляются только пакеты, которых не было до установки скрипта:'
    printf '  %s\n' $packages
    apt-get remove -y $packages || true
  fi

  local ufw_was_active
  ufw_was_active=$(python3 - "$state_file" <<'PY'
import json,sys
print(str(json.load(open(sys.argv[1])).get('ufw_was_active',False)).lower())
PY
)
  if command -v ufw >/dev/null; then
    if [[ "$ufw_was_active" == true ]]; then
      ufw reload >/dev/null 2>&1 || true
    else
      ufw disable >/dev/null 2>&1 || true
    fi
  fi

  python3 - "$state_file" <<'PY'
import json,subprocess,sys
s=json.load(open(sys.argv[1]))
for svc,meta in s.get('services_before',{}).items():
    if meta.get('enabled'):
        subprocess.run(['systemctl','enable',svc],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    else:
        subprocess.run(['systemctl','disable',svc],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if meta.get('active'):
        subprocess.run(['systemctl','start',svc],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    else:
        subprocess.run(['systemctl','stop',svc],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
PY

  # Config files were restored above. Reload nginx after restoring its service
  # state so old worker processes do not keep removed 9443 listeners open.
  if command -v nginx >/dev/null && systemctl is-active --quiet nginx; then
    if nginx -t && systemctl reload nginx; then
      nginx_reload_status='reloaded'
    else
      nginx_reload_status='failed'
    fi
  fi

  python3 - "$state_file" <<'PY'
import json,time,sys
p=sys.argv[1]
s=json.load(open(p)); s['removed']=True; s['removed_at']=int(time.time())
with open('/root/selfsteal-3xui/state.json','w') as f:
    json.dump(s,f,indent=2); f.write('\n')
PY
  chmod 600 /root/selfsteal-3xui/state.json

  echo
  echo 'Удаление завершено.'
  echo 'Предсуществующие конфигурации восстановлены.'
  if [[ "$nginx_reload_status" == reloaded ]]; then
    echo 'Конфигурация nginx перечитана.'
  elif [[ "$nginx_reload_status" == failed ]]; then
    echo 'ВНИМАНИЕ: nginx не перечитал конфигурацию; старый listener может оставаться активным. Проверьте nginx -t и выполните systemctl reload nginx.'
  fi
  echo 'Резервные копии и результаты оставлены в /root/selfsteal-3xui/.'
  exit 0
}

[[ $EUID == 0 ]] || fail 'Запустите через sudo selfsteal или sudo bash setup-selfsteal-3xui.sh.'
case "$ACTION" in
  install-script) install_script_command; exit 0 ;;
  uninstall-script) uninstall_script_command; exit 0 ;;
  update-script) update_script_command; exit 0 ;;
esac
[[ -r /etc/os-release ]] || fail 'Не найден файл с информацией об операционной системе.'
. /etc/os-release
[[ $ID == ubuntu || $ID == debian ]] || fail 'Поддерживаются только Ubuntu и Debian.'
[[ -d /run/systemd/system ]] || fail 'Требуется система с работающим systemd.'
command -v systemctl >/dev/null || fail 'Не найден systemctl; требуется система с работающим systemd.'

if [[ "$ACTION" == menu ]]; then
  if [[ ! -e "$SCRIPT_COMMAND" && ! -L "$SCRIPT_COMMAND" ]]; then
    install_script_command
  fi
  show_menu
fi
case "$ACTION" in
  uninstall-script) uninstall_script_command; exit 0 ;;
  update-script) update_script_command; exec "$SCRIPT_COMMAND" --menu ;;
  vps-tests) show_vps_tests_menu; exit 0 ;;
  uninstall) uninstall_script ;;
  status) status_report ;;
  masking-audit) masking_audit; exit $? ;;
esac

(( CHECK )) || [[ -t 0 ]] || fail 'Требуется интерактивный терминал.'
PREFLIGHT_PACKAGES=()
command -v python3 >/dev/null || PREFLIGHT_PACKAGES+=(python3)
if ! command -v ss >/dev/null || ! command -v ip >/dev/null; then PREFLIGHT_PACKAGES+=(iproute2); fi
command -v flock >/dev/null || PREFLIGHT_PACKAGES+=(util-linux)
if (( ${#PREFLIGHT_PACKAGES[@]} )); then
  (( ! CHECK )) || fail "Проверка без изменений невозможна: отсутствуют пакеты ${PREFLIGHT_PACKAGES[*]}. Установка пакетов не выполнялась."
  command -v apt-get >/dev/null || fail 'В системе отсутствует apt-get.'
  printf 'Отсутствуют утилиты предварительной проверки. Установить только: %s\n' "${PREFLIGHT_PACKAGES[*]}"
  echo 'Предварительная установка не настраивает nginx, панель и межсетевой экран. При последующих ошибках проверки или настройки установленные пакеты сохраняются.'
  read -r -p 'Для подтверждения введите INSTALL PREFLIGHT PACKAGES (иначе отмена): ' ANSWER
  [[ $ANSWER == 'INSTALL PREFLIGHT PACKAGES' ]] || fail 'Отменено до установки зависимостей.'
  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PREFLIGHT_PACKAGES[@]}"
  for command in python3 ss ip flock; do command -v "$command" >/dev/null || fail "Утилита $command по-прежнему недоступна после установки пакетов."; done
fi
# Lock an existing inode: even --check creates no lock file.
exec 9</etc/os-release
flock -n 9 || fail 'Уже запущен другой экземпляр настройки.'
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
# Snapshot service state before setup changes anything; uninstall restores these values.
SERVICES_BEFORE_JSON=$(python3 - "${SERVICES[@]}" <<'PY'
import json,subprocess,sys
state={}
for service in sys.argv[1:]:
    active=subprocess.run(['systemctl','is-active','--quiet',service],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode == 0
    enabled=subprocess.run(['systemctl','is-enabled','--quiet',service],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode == 0
    state[service]={'active':active,'enabled':enabled}
print(json.dumps(state,separators=(',',':')))
PY
)
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
import hashlib
import http.cookiejar
import http.client
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import socket
import sqlite3
import ssl
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
        raise RuntimeError('Ошибка команды 3x-ui (вывод скрыт для защиты секретных данных)')
    return p.stdout


def require_version(state):
    version = run([state['panel_binary'], '-v'], state).strip().removeprefix('v')
    if version != VERSION:
        raise RuntimeError('Неподдерживаемая версия 3x-ui: поддерживается только проверенная 3.8.5; обновление не выполнялось')
    state['panel_version'] = version


def db_read(state):
    return sqlite3.connect(Path(state['panel_db']).as_uri() + '?mode=ro', uri=True)


def inspect(state):
    exists = Path(state['panel_db']).exists()
    binary = Path(state['panel_binary']).exists()
    if exists != binary:
        raise RuntimeError('Обнаружена неполная установка 3x-ui; исправьте ее перед настройкой')
    state['is_existing'] = exists
    matches = []
    if exists:
        require_version(state)
        with db_read(state) as db:
            settings = dict(db.execute('SELECT key,value FROM settings'))
            db.row_factory = sqlite3.Row
            inbounds = [dict(r) for r in db.execute('SELECT * FROM inbounds WHERE port=443 AND (node_id IS NULL OR node_id=0)')]
        for row in inbounds:
            if inbound_uses_udp(row):
                continue
            stream = parse(row['stream_settings'])
            if row['protocol'] != 'vless' or stream.get('security') != 'reality':
                raise RuntimeError('Существующее локальное входящее подключение панели на порту 443 несовместимо; изменений нет')
            if stream.get('network') not in ('tcp', 'raw'):
                raise RuntimeError('Существующее подключение Reality на порту 443 использует транспорт, отличный от TCP/raw; перенос нарушит работу клиентов')
            if row.get('disable_flow'):
                raise RuntimeError('В существующем входящем подключении отключены все flow клиентов; нельзя добавить Vision без изменения старых клиентов')
            matches.append(row)
        if len(matches) > 1:
            raise RuntimeError('Несколько локальных входящих подключений на порту 443 требуют ручного согласования')
        if settings.get('webListen', '') not in ('127.0.0.1', '::1'):
            raise RuntimeError('Существующая панель слушает внешний адрес. Ограничьте ее локальным адресом перед настройкой; параметры администратора не изменяются')
        if any(settings.get(k, 'false') == 'true' for k in ('subEnable', 'subJsonEnable', 'subClashEnable')) and settings.get('subListen', '') not in ('127.0.0.1', '::1'):
            raise RuntimeError('Существующий сервис подписок слушает внешний адрес; ограничьте его локальным адресом перед настройкой')
        host = settings['webListen']
        host = '[' + host + ']' if ':' in host else host
        scheme = 'https' if settings.get('webCertFile') and settings.get('webKeyFile') else 'http'
        base_path = '/' + settings.get('webBasePath', '/').strip('/')
        if base_path != '/':
            base_path += '/'
        detected_url = '%s://%s:%s%s' % (scheme, host, settings.get('webPort', '2053'), base_path)
        if state.get('panel_url') and state['panel_url'].rstrip('/') != detected_url.rstrip('/'):
            raise RuntimeError('Введенный URL панели не совпадает с настроенным локальным адресом или basePath')
        state['panel_url'] = detected_url
        if state.get('publish_panel'):
            panel_route(state)
        state['inbound_id'] = matches[0]['id'] if matches else None
    else:
        state['inbound_id'] = None
        # Plan the fresh route before nginx preflight; bootstrap must reuse it.
        state['panel_port'] = int(state.get('panel_port', 2053))
        state['panel_url'] = 'http://127.0.0.1:%d/%s/' % (
            state['panel_port'], secrets.token_urlsafe(24))
    ss = subprocess.run(['ss', '-H', '-ltnp', 'sport = :443'], capture_output=True, text=True, check=True).stdout
    if ss.strip() and not matches:
        raise RuntimeError('TCP 443 занят сервисом, отличным от совместимого локального подключения Reality в 3x-ui; сервисы не будут остановлены')
    if ss.strip() and any('xray' not in line.lower() for line in ss.splitlines()):
        raise RuntimeError('Не удалось подтвердить, что TCP 443 занят Xray; перехват порта отменен')


def bcrypt_password(password):
    libname = ctypes.util.find_library('crypt')
    if not libname:
        raise RuntimeError('Для безопасной первоначальной настройки требуется libcrypt с поддержкой bcrypt')
    lib = ctypes.CDLL(libname)
    lib.crypt.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    lib.crypt.restype = ctypes.c_char_p
    # bcrypt salt uses its own alphabet; 22 chars represent 128 bits.
    alphabet = './ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    salt = ''.join(secrets.choice(alphabet) for _ in range(21)) + secrets.choice('.Oeu')
    hashed = lib.crypt(password.encode(), ('$2b$12$' + salt).encode())
    if not hashed or not hashed.startswith(b'$2b$12$') or len(hashed) != 60:
        raise RuntimeError('Системная libcrypt не может создать bcrypt; безопасная первоначальная настройка остановлена')
    return hashed.decode()


def bootstrap(state):
    if state.get('is_existing') or Path(state['panel_db']).exists():
        raise RuntimeError('Первоначальная настройка доступна только для новой установки; существующие учетные данные не сбрасываются')
    require_version(state)
    port = int(state.get('panel_port', 2053))
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', port))
    username = 'admin_' + secrets.token_hex(10)
    password = secrets.token_urlsafe(36)
    hashed = bcrypt_password(password)
    path, _ = panel_route(state)
    Path(state['panel_db']).parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    run([state['panel_binary'], 'setting', '-listenIP', '127.0.0.1', '-port', str(port), '-webBasePath', path], state)
    # Only this newly initialized, never-started DB is written directly. The CLI
    # has no password-on-stdin interface; this avoids credentials in process argv.
    os.chmod(state['panel_db'], 0o600)
    with sqlite3.connect(state['panel_db']) as db:
        if db.execute('SELECT count(*) FROM users').fetchone()[0] != 1:
            raise RuntimeError('Неожиданное число администраторов новой установки; сервис должен оставаться остановленным')
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
            raise RuntimeError('Проверка безопасности первоначальной настройки не пройдена')
    state.update(panel_username=username, panel_password=password, panel_port=port,
                 panel_url='http://127.0.0.1:%d%s' % (port, path), bootstrap_complete=True)


def panel_route(state):
    panel = urllib.parse.urlsplit(state['panel_url'])
    if (panel.scheme not in ('http', 'https') or not panel.hostname
            or not ipaddress.ip_address(panel.hostname).is_loopback
            or panel.username or panel.password or panel.query or panel.fragment):
        raise RuntimeError('Адрес назначения публичного маршрута панели должен содержать локальный IP-адрес')
    if not re.fullmatch(r'/[A-Za-z0-9_-]{20,128}/', panel.path):
        raise RuntimeError('Для публикации панели требуется уникальный случайный basePath (от 20 символов, безопасных для URL). Задайте его вручную в 3x-ui через SSH-туннель и повторите запуск; настройки панели не изменены')
    origin = urllib.parse.urlunsplit((panel.scheme, panel.netloc, '', '', ''))
    return panel.path, origin


def nginx_nodes(text):
    # Preserve source offsets; braces inside comments/quoted values are not syntax.
    tokens = []
    pattern = re.compile(r'\s+|#[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{};]|[^\s{};#"\']+')
    end = 0
    for m in pattern.finditer(text):
        if m.start() != end:
            raise RuntimeError('Не удалось безопасно разобрать пользовательскую конфигурацию nginx')
        end = m.end()
        raw = m.group()
        if raw.isspace() or raw.startswith('#'):
            continue
        if '\\' in raw:
            raise RuntimeError('Экранирование в конфигурации nginx требует ручной настройки маршрута')
        tokens.append((raw.strip('"\''), m.start(), m.end()))
    if end != len(text):
        raise RuntimeError('Не удалось безопасно разобрать пользовательскую конфигурацию nginx')
    pos = 0
    def block(nested=False):
        nonlocal pos
        nodes = []
        while pos < len(tokens):
            if tokens[pos][0] == '}':
                if not nested:
                    raise RuntimeError('Неожиданная закрывающая скобка в конфигурации nginx')
                close = tokens[pos][1]
                pos += 1
                return nodes, close
            start = tokens[pos][1]
            words = []
            while pos < len(tokens) and tokens[pos][0] not in ('{', '}', ';'):
                words.append(tokens[pos][0])
                pos += 1
            if not words or pos == len(tokens) or tokens[pos][0] == '}':
                raise RuntimeError('Незавершенная директива nginx')
            delimiter = tokens[pos]
            pos += 1
            children, close = block(True) if delimiter[0] == '{' else (None, delimiter[1])
            finish = tokens[pos - 1][2]
            nodes.append(dict(words=words, children=children, start=start, end=finish, close=close))
        if nested:
            raise RuntimeError('Незакрытый блок nginx')
        return nodes, len(text)
    return block()[0]

def connection_map(state):
    name = '$selfsteal_connection_' + hashlib.sha256(state['domain'].encode()).hexdigest()[:16]
    return name, f"# Managed by selfsteal-3xui: {state['domain']}\nmap $http_upgrade {name} {{ default upgrade; '' close; }}\n"



def route_snippet(state):
    path, origin = panel_route(state)
    connection, _ = connection_map(state)
    return f'''# Managed by selfsteal-3xui: {state['domain']}
location = {path[:-1]} {{ return 308 {path}; }}
location ^~ {path} {{
    proxy_pass {origin};
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $proxy_protocol_addr;
    proxy_set_header X-Forwarded-For $proxy_protocol_addr;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection {connection};
    proxy_read_timeout 3600s;
    proxy_buffering off;
}}
'''


def plan_route(state):
    site = state.get('nginx_site')
    map_path = Path(state['panel_map'])
    _, map_contents = connection_map(state)
    state['panel_route_status'] = 'disabled'
    state['public_url'] = None
    state['script_exposed_public_admin'] = False
    if not site:
        if any(Path(state[k]).exists() or Path(state[k]).is_symlink() for k in ('panel_snippet', 'panel_map')):
            raise RuntimeError('Управляемый файл панели существует без TLS-сайта домена; проверьте вручную')
        return None
    target = Path(site).resolve(strict=True)
    text = target.read_text()
    nodes = nginx_nodes(text)
    servers = [n for n in nodes if n['words'] == ['server'] and n['children'] is not None
               and any(c['words'][0] == 'server_name' and state['domain'] in c['words'][1:] for c in n['children'])
               and any(c['words'][0] == 'listen' and '127.0.0.1:9443' in c['words'] and 'ssl' in c['words'] and 'proxy_protocol' in c['words'] for c in n['children'])]
    if len(servers) != 1:
        raise RuntimeError('Не удалось однозначно выбрать TLS-сервер домена для маршрута панели')
    server = servers[0]
    snippet = Path(state['panel_snippet'])
    marker = re.compile(r'(?m)^    # selfsteal-3xui-panel ([0-9a-f]{64})\n    include ' + re.escape(str(snippet)) + r';\n')
    owned = list(marker.finditer(text))
    if len(owned) > 1:
        raise RuntimeError('Обнаружены дубликаты управляемых include панели')
    if owned:
        m = owned[0]
        if not (server['start'] < m.start() < m.end() < server['end']) or not snippet.is_file() or snippet.is_symlink():
            raise RuntimeError('Нарушена связь управляемого include панели с ее фрагментом конфигурации')
        contents = snippet.read_bytes()
        if hashlib.sha256(contents).hexdigest() != m[1] or not contents.startswith(('# Managed by selfsteal-3xui: ' + state['domain'] + '\n').encode()):
            raise RuntimeError('Управляемый фрагмент панели изменен вручную; замена или удаление отменены')
        if map_path.is_symlink() or not map_path.is_file() or map_path.read_text() != map_contents:
            raise RuntimeError('Управляемый WebSocket map изменен или удален вручную; изменения отменены')
        clean = text[:m.start()] + text[m.end():]
    else:
        if snippet.exists() or snippet.is_symlink():
            raise RuntimeError('Фрагмент панели существует без связанного include; проверьте вручную')
        if map_path.exists() or map_path.is_symlink():
            raise RuntimeError('WebSocket map существует без связанного include панели; проверьте вручную')
        clean = text
    if not state.get('publish_panel'):
        # Custom public routes are deliberately outside our ownership.
        state['panel_route_status'] = 'disabled-managed-route-removed' if owned else 'disabled-custom-routes-preserved'
        return target, snippet, clean, None
    path, origin = panel_route(state)
    children = nginx_nodes(clean)
    selected = next(n for n in children if n['start'] == server['start'])
    custom_route = False
    custom_redirect = False
    for node in selected['children']:
        words = node['words']
        if words[0] == 'include':
            raise RuntimeError('Пользовательские include TLS-сервера требуют ручной настройки маршрута панели; замены не выполнялись')
        if words[0] != 'location':
            continue
        if '~' in words[1] or words[1].startswith('@'):
            raise RuntimeError('Пользовательские регулярные или именованные location требуют ручной настройки маршрута панели')
        route = words[-1]
        if route == '/':
            continue
        if route.rstrip('/') == path.rstrip('/') or route.startswith(path) or path.startswith(route.rstrip('/') + '/'):
            directives = [c['words'] for c in node['children'] or []]
            if (not owned and words == ['location', '=', path[:-1]]
                    and directives == [['return', '308', path]]):
                custom_redirect = True
                continue
            headers = {w[1]: w[2] for w in directives if len(w) == 3 and w[0] == 'proxy_set_header'}
            if (not owned and route == path and (words == ['location', '^~', path] or words == ['location', path])
                    and ['proxy_pass', origin] in directives
                    and ['proxy_http_version', '1.1'] in directives
                    and headers.get('Upgrade') == '$http_upgrade'
                    and headers.get('Connection') in ('upgrade', '$connection_upgrade')
                    and not any(w[0] in ('rewrite', 'return', 'proxy_pass_request_headers') for w in directives)):
                custom_route = True
                continue
            raise RuntimeError('Пользовательский location конфликтует с basePath панели; маршруты не заменены')
    if custom_route:
        state.update(panel_route_status='existing-custom-route-preserved',
                     public_url='https://' + state['domain'] + path)
        return target, snippet, text, None
    if custom_redirect:
        raise RuntimeError('Пользовательское перенаправление существует без совместимого прокси панели; настройте вручную')
    contents = route_snippet(state)
    digest = hashlib.sha256(contents.encode()).hexdigest()
    insertion = f'    # selfsteal-3xui-panel {digest}\n    include {snippet};\n'
    close = selected['close']
    clean = clean[:close] + insertion + clean[close:]
    state.update(panel_route_status='enabled-managed-route', public_url='https://' + state['domain'] + path,
                 script_exposed_public_admin=True)
    return target, snippet, clean, contents


def route_preflight(state):
    plan_route(state)


def publish(state):
    plan = plan_route(state)
    if not plan:
        return
    target, snippet, text, contents = plan
    if contents is not None:
        snippet.parent.mkdir(parents=True, exist_ok=True)
        snippet.write_text(contents)
        os.chmod(snippet, 0o600)
        map_path = Path(state['panel_map'])
        map_path.parent.mkdir(parents=True, exist_ok=True)
        map_path.write_text(connection_map(state)[1])
        os.chmod(map_path, 0o600)
    elif state.get('panel_route_status') == 'disabled-managed-route-removed':
        snippet.unlink()
        Path(state['panel_map']).unlink()
    if target.read_text() != text:
        target.write_text(text)


def panel_route_response(state):
    # Probe live nginx locally through its TLS/PROXY listener, without relying on DNS.
    path, _ = panel_route(state)
    with socket.create_connection(('127.0.0.1', 9443), timeout=3) as raw:
        raw.sendall(b'PROXY TCP4 127.0.0.1 127.0.0.1 12345 9443\r\n')
        with ssl.create_default_context().wrap_socket(raw, server_hostname=state['domain']) as tls:
            request = ('GET ' + path + 'csrf-token HTTP/1.1\r\nHost: ' + state['domain']
                       + '\r\nConnection: close\r\n\r\n')
            tls.sendall(request.encode('ascii'))
            response = http.client.HTTPResponse(tls)
            response.begin()
            body = response.read(1048576)
            status = response.status
    return status, body


def check_panel_route(state, enabled):
    # reload signals nginx; newly started workers may not be ready immediately.
    deadline = time.monotonic() + 15
    last = 'нет ответа'
    while True:
        try:
            status, body = panel_route_response(state)
            last = 'HTTP ' + str(status)
            if enabled:
                try:
                    result = json.loads(body)
                except (ValueError, UnicodeError):
                    result = {}
                if (status == 200 and isinstance(result, dict) and result.get('success') is True
                        and isinstance(result.get('obj'), str) and result['obj']):
                    return
            elif status in (403, 404, 410):
                return
        except (OSError, http.client.HTTPException) as exc:
            last = type(exc).__name__
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            action = 'открытие' if enabled else 'закрытие'
            raise RuntimeError('Не удалось подтвердить ' + action + ' HTTPS-маршрута панели за 15 секунд (' + last + ')')
        time.sleep(min(0.25, remaining))


def panel_access(state, enabled, install_state):
    if state.get('removed'):
        raise RuntimeError('Установка удалена; сначала выполните установку')
    if not state.get('domain') or not state.get('nginx_site'):
        raise RuntimeError('Не сохранены домен или TLS-сайт установки')
    # Read current settings; never publish a stale address or a directly exposed listener.
    with db_read(state) as db:
        settings = dict(db.execute('SELECT key,value FROM settings'))
    host = settings.get('webListen', '')
    if host not in ('127.0.0.1', '::1'):
        raise RuntimeError('Панель слушает внешний адрес; ограничьте webListen локальным адресом в 3x-ui')
    host_url = '[' + host + ']' if ':' in host else host
    scheme = 'https' if settings.get('webCertFile') and settings.get('webKeyFile') else 'http'
    path = '/' + settings.get('webBasePath', '/').strip('/') + '/'
    panel_url = '%s://%s:%s%s' % (scheme, host_url, settings.get('webPort', '2053'), path)
    if panel_url != state.get('panel_url'):
        raise RuntimeError('Параметры панели изменены; повторите настройку для сохранения актуального локального URL')
    panel_route(state)
    proposed = copy.deepcopy(state)
    proposed['publish_panel'] = enabled
    plan = plan_route(proposed)
    if not plan or proposed.get('panel_route_status') == 'existing-custom-route-preserved':
        raise RuntimeError('Маршрут панели не принадлежит скрипту; измените пользовательский прокси вручную')
    target, snippet, clean, _ = plan
    # On disable, ensure another location/include will not keep this panel reachable.
    if not enabled:
        _, origin = panel_route(state)
        servers = [n for n in nginx_nodes(clean) if n['words'] == ['server']
                   and any(c['words'][0] == 'server_name' and state['domain'] in c['words'][1:]
                           for c in n['children'] or [])]
        def check_nodes(nodes):
            for node in nodes:
                words = node['words']
                if words[0] == 'include' or (words[0] == 'proxy_pass' and (words[1].rstrip('/') == origin or words[1].startswith(origin + '/'))):
                    raise RuntimeError('Пользовательский маршрут/include может публиковать панель; отключение требует ручной проверки')
                check_nodes(node['children'] or [])
        for server in servers:
            check_nodes(server['children'] or [])
    subprocess.run(['nginx', '-t'], check=True)
    subprocess.run(['systemctl', 'is-active', '--quiet', 'nginx'], check=True)
    canonical = Path(install_state)
    access = Path(state['result_dir']) / 'access.json'
    paths = [target, snippet, Path(state['panel_map']), access, canonical]
    original = {}
    for file in paths:
        if file.is_symlink() or (file.exists() and not file.is_file()):
            raise RuntimeError('Путь конфигурации или состояния не является обычным файлом: ' + str(file))
        original[file] = (file.read_bytes(), file.stat().st_mode & 0o777) if file.exists() else None
    backup = canonical.parent / 'backups' / ('panel-access-' + time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '-' + secrets.token_hex(4))
    backup.mkdir(mode=0o700, parents=True)
    for index, (file, data) in enumerate(original.items()):
        if data:
            saved = backup / str(index)
            saved.write_bytes(data[0]); os.chmod(saved, 0o600)
    secure_json(backup / 'manifest.json', [{'path': str(file), 'exists': data is not None,
                 'mode': data[1] if data else None} for file, data in original.items()])
    try:
        publish(proposed)
        subprocess.run(['nginx', '-t'], check=True)
        subprocess.run(['systemctl', 'reload', 'nginx'], check=True)
        check_panel_route(proposed, enabled)
        if not enabled:
            proposed['panel_route_status'] = 'disabled-managed-route-removed'
        if access.exists():
            result = json.loads(access.read_text())
            result.update(public_panel_enabled=enabled, public_url=proposed.get('public_url'),
                          public_panel_status=proposed['panel_route_status'],
                          script_exposed_public_admin=enabled)
            secure_json(access, result)
        proposed['panel_access_backup'] = str(backup)
        secure_json(canonical, proposed)
    except BaseException:
        for file, data in original.items():
            if data is None:
                file.unlink(missing_ok=True)
            else:
                file.write_bytes(data[0]); os.chmod(file, data[1])
        try:
            subprocess.run(['nginx', '-t'], check=True)
            subprocess.run(['systemctl', 'reload', 'nginx'], check=True)
        except Exception as rollback_error:
            raise RuntimeError('Файлы восстановлены, но nginx не перечитал прежнюю конфигурацию; проверьте nginx -t и reload. Резервная копия: ' + str(backup)) from rollback_error
        print('Переключение отменено: прежний доступ к панели и конфигурация nginx восстановлены.', file=sys.stderr)
        raise
    state.clear(); state.update(proposed)
    print('Доступ к панели из интернета: ' + ('ВКЛЮЧЁН' if enabled else 'ВЫКЛЮЧЕН'))
    if enabled:
        print('URL панели: ' + state['public_url'])
    print('Локальный доступ и SSH-туннель сохранены. Резервная копия: ' + str(backup))


class API:
    def __init__(self, state):
        self.base = state['panel_url'].rstrip('/') + '/'
        url = urllib.parse.urlsplit(self.base)
        if url.scheme not in ('http', 'https') or not url.hostname or not ipaddress.ip_address(url.hostname).is_loopback or url.username or url.password or url.query or url.fragment:
            raise RuntimeError('URL API панели должен содержать локальный IP-адрес и basePath')
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
            raise RuntimeError('Ошибка запроса API панели: ' + path + ' (учетные данные и конфигурация скрыты)') from None
        if not obj.get('success'):
            raise RuntimeError('API панели отклонил запрос: ' + path + ' (ответ скрыт)')
        return obj.get('obj')

    def list(self):
        return self.call('panel/api/inbounds/list') or []

    def restart(self):
        self.call('panel/api/server/restartXrayService', {})


def public_key(private):
    key = base64.urlsafe_b64decode(private + '=' * (-len(private) % 4))
    if len(key) != 32:
        raise RuntimeError('Закрытый ключ Reality не является 32-байтовым ключом X25519')
    # RFC8410 PKCS8/SPKI encoding. OpenSSL receives private material only on
    # stdin, never in argv, environment, a temporary file, or diagnostics.
    der = bytes.fromhex('302e020100300506032b656e04220420') + key
    result = subprocess.run(['openssl', 'pkey', '-inform', 'DER', '-pubout', '-outform', 'DER'],
                            input=der, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    prefix = bytes.fromhex('302a300506032b656e032100')
    if result.returncode or not result.stdout.startswith(prefix) or len(result.stdout) != len(prefix) + 32:
        raise RuntimeError('Не удалось получить открытый ключ X25519 через OpenSSL')
    return base64.urlsafe_b64encode(result.stdout[len(prefix):]).decode().rstrip('=')


def pick(inbounds):
    matches = [i for i in inbounds if int(i.get('port') or 0) == 443 and not i.get('nodeId')
               and not inbound_uses_udp(i)]
    if len(matches) > 1:
        raise RuntimeError('Несколько локальных входящих подключений на порту 443 не поддерживаются')
    if matches and (matches[0]['protocol'] != 'vless' or parse(matches[0]['streamSettings']).get('security') != 'reality'):
        raise RuntimeError('Локальное входящее подключение на порту 443 несовместимо')
    if matches and parse(matches[0]['streamSettings']).get('network') not in ('tcp', 'raw'):
        raise RuntimeError('Существующее подключение Reality на порту 443 использует транспорт, отличный от TCP/raw; перенос нарушит работу клиентов')
    if matches and matches[0].get('disableFlow'):
        raise RuntimeError('В существующем входящем подключении отключены все flow клиентов; нельзя добавить Vision без изменения старых клиентов')
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
        raise RuntimeError('Поле allowedIPs не соответствует проверенной схеме model.Client')
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
                raise RuntimeError('Пустой flow входящего подключения конфликтует с требуемым flow Vision; исправьте перед настройкой')
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
            raise RuntimeError('Отсутствует существующий ключ Reality или shortIds; идентификаторы не будут созданы заново')
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
            raise RuntimeError('Конфликт идентификатора нового клиента скрипта; изменений нет')
        state['panel_rollback']['created_client'] = {
            'email': created_client['email'], 'uuid': created_client['id'],
            'subId': created_client['subId']}
        save()
    domain = state['domain']
    primary_target, primary_xver = chain_primary_endpoint(state)
    reality.update(target=primary_target, serverNames=[domain], xver=primary_xver)
    reality.pop('dest', None)
    reality.setdefault('settings', {}).update(publicKey=public_key(reality['privateKey']), fingerprint='firefox', serverName=domain, spiderX='/')
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


def host_group_has_address(group, domain, port=443):
    hosts = group.get('hosts') or []
    return hosts in ([domain], ['%s:%d' % (domain, port)])


def terminal_label(value):
    return ''.join(char if char.isprintable() else '?' for char in str(value))


def choose_existing_client(api):
    clients = api.call('panel/api/clients/list') or []
    eligible = []
    for client in clients:
        try:
            uuid.UUID(client.get('uuid') or '')
        except (ValueError, AttributeError, TypeError):
            continue
        if client.get('email'):
            eligible.append(client)
    eligible.sort(key=lambda client: str(client['email']).casefold())
    if not eligible:
        raise RuntimeError('Нет существующих пользователей с UUID для VLESS. Добавьте пользователя в панели и повторите пункт 2.')
    print('\n--- Привязка к пользователю ---')
    for number, client in enumerate(eligible, 1):
        status = 'включён' if client.get('enable', True) else 'выключен'
        print('  %d) %s [%s]' % (number, terminal_label(client['email']), status))
    print('  0) Отмена')
    while True:
        try:
            answer = input('Выберите пользователя [1-%d, 0]: ' % len(eligible)).strip()
        except (EOFError, KeyboardInterrupt):
            raise RuntimeError('Отменено до создания inbound') from None
        if answer == '0':
            raise RuntimeError('Отменено до создания inbound')
        if answer.isascii() and answer.isdigit() and 1 <= int(answer) <= len(eligible):
            selected = eligible[int(answer) - 1]
            snapshot = canonical_client(api, selected['email'])
            if snapshot['client'].get('uuid') != selected['uuid']:
                raise RuntimeError('Выбранный пользователь изменился; повторите выбор')
            client_update_payload(snapshot)  # Validate the canonical schema before mutation.
            if snapshot['client'].get('flow', '') not in ('', 'xtls-rprx-vision'):
                raise RuntimeError('Flow выбранного пользователя несовместим с VLESS + Reality/TCP')
            return snapshot
        print('Введите номер пользователя из списка или 0 для отмены.')


def check_client_binding(api, snapshot, inbound_ids):
    current = canonical_client(api, snapshot['client']['email'])
    if (current['client'].get('uuid') != snapshot['client']['uuid']
            or client_behavior(current) != client_behavior(snapshot)
            or set(current.get('inboundIds') or []) != set(inbound_ids)):
        raise RuntimeError('Не удалось подтвердить привязку и сохранность параметров пользователя')
    return current


def chain_primary_endpoint(state):
    added = state.get('added_inbounds') or []
    chained = bool(state.get('reality_chain') and added)
    port = added[0]['port'] if chained else state.get('target_port', 9443)
    return '127.0.0.1:%d' % int(port), 0 if chained else 1


def chain_plan(api, state, extra=None):
    all_rows = api.list()
    records = [{'id': state['inbound_id'], 'port': 443}] + list(state.get('added_inbounds') or [])
    if extra:
        records.append({'id': extra['id'], 'port': extra['port']})
    ids = [int(record['id']) for record in records]
    ports = [int(record['port']) for record in records]
    nginx_port = int(state.get('target_port', 9443))
    if (len(set(ids)) != len(ids) or len(set(ports)) != len(ports)
            or nginx_port in ports or any(not 1 <= port <= 65535 for port in ports)):
        raise RuntimeError('Конфликт ID или портов в сохранённой цепочке Reality')
    plan = []
    credentials = []
    for index, record in enumerate(records):
        matches = [row for row in all_rows if int(row.get('id') or 0) == int(record['id'])]
        if len(matches) != 1:
            raise RuntimeError('Сохранённый inbound ID %s не найден; цепочка не изменена' % record['id'])
        before = matches[0]
        stream = copy.deepcopy(parse(before['streamSettings']))
        reality = stream.get('realitySettings') or {}
        if (before.get('nodeId') or not before.get('enable', True)
                or before.get('protocol') != 'vless' or int(before.get('port') or 0) != int(record['port'])
                or (index and before.get('tag') != 'selfsteal-reality-%d' % int(record['port']))
                or stream.get('security') != 'reality' or stream.get('network') not in ('tcp', 'raw')
                or not reality.get('privateKey') or not reality.get('shortIds')
                or reality.get('serverNames') != [state['domain']]):
            raise RuntimeError('Inbound ID %s не соответствует сохранённой локальной настройке Reality' % record['id'])
        if before.get('listen') not in ('', None, '0.0.0.0', '127.0.0.1', '::', '::0'):
            raise RuntimeError('Inbound цепочки недоступен через loopback; проверьте поле listen')
        if any(key == reality['privateKey'] and set(short_ids) & set(reality['shortIds'])
               for key, short_ids in credentials):
            raise RuntimeError('У двух inbound совпадают Reality-ключ и Short ID; цепочка не сможет различать их')
        credentials.append((reality['privateKey'], reality['shortIds']))
        port = ports[index + 1] if index + 1 < len(ports) else nginx_port
        reality.update(target='127.0.0.1:%d' % port, xver=0 if index + 1 < len(ports) else 1)
        reality.pop('dest', None)
        reality.setdefault('settings', {}).update(publicKey=public_key(reality['privateKey']), fingerprint='firefox')
        stream['realitySettings'] = reality
        after = copy.deepcopy(before)
        after['streamSettings'] = json.dumps(stream)
        plan.append((before, after))
    return plan


def wait_chain_runtime(state, plan):
    path = Path(state.get('runtime_config', str(Path(state['panel_binary']).parent / 'bin/config.json')))
    for _ in range(30):
        try:
            runtime = json.loads(path.read_text())
            for _, inbound in plan:
                matches = [row for row in runtime.get('inbounds', [])
                           if row.get('tag') == inbound['tag'] and row.get('port') == inbound['port']]
                if len(matches) != 1 or matches[0].get('protocol') != 'vless':
                    raise ValueError('missing runtime inbound')
                row = matches[0]
                expected = parse(inbound['streamSettings'])['realitySettings']
                actual = row.get('streamSettings', {}).get('realitySettings', {})
                if (actual.get('target', actual.get('dest')) != expected['target']
                        or actual.get('xver', 0) != expected['xver']
                        or any(actual.get(key) != expected.get(key) for key in ('privateKey', 'shortIds', 'serverNames'))):
                    raise ValueError('runtime Reality differs')
                stats = {stat['email']: stat.get('enable', True) for stat in inbound.get('clientStats', [])}
                expected_clients = set()
                for client in parse(inbound['settings']).get('clients', []):
                    if not client_active(client, inbound) or not stats.get(client.get('email'), True):
                        continue
                    flow = client.get('flow', '')
                    if flow == 'xtls-rprx-vision-udp443':
                        flow = 'xtls-rprx-vision'
                    expected_clients.add((client['id'], '' if inbound.get('disableFlow') else flow))
                actual_clients = {(client['id'], client.get('flow', ''))
                                  for client in row.get('settings', {}).get('clients', [])}
                if actual_clients != expected_clients:
                    raise ValueError('runtime clients differ')
                with socket.create_connection(('127.0.0.1', inbound['port']), timeout=0.5):
                    pass
            return
        except (OSError, ValueError, KeyError, TypeError):
            time.sleep(1)
    raise RuntimeError('Xray не подтвердил все переходы и пользователей цепочки Reality')


def restore_chain(api, state, save):
    journal = state.get('pending_chain')
    if not journal:
        return
    errors = []
    originals = [before for before in journal['before'] if before['id'] != journal.get('new_id')]
    for before in reversed(originals):
        try:
            api.call('panel/api/inbounds/update/%s' % before['id'], payload(before))
        except Exception:
            errors.append(str(before['id']))
    try:
        api.restart()
        current = {row['id']: row for row in api.list()}
        for before in originals:
            actual = current[before['id']]
            if (parse(actual['streamSettings']) != parse(before['streamSettings'])
                    or parse(actual['settings']) != parse(before['settings'])):
                raise RuntimeError('Панель не подтвердила восстановление исходных параметров')
        for snapshot in journal.get('clients', []):
            check_client_binding(api, snapshot, snapshot.get('inboundIds') or [])
        wait_chain_runtime(state, [(before, before) for before in originals])
    except Exception:
        errors.append('Xray restart')
    if errors:
        journal['rollback_incomplete'] = errors
        save()
        raise RuntimeError('Откат цепочки не завершён; сохранена закрытая копия исходных настроек')
    state.pop('pending_chain', None)
    save()


def apply_chain(api, state, save, extra=None):
    if state.get('pending_chain'):
        raise RuntimeError('Есть незавершённое изменение цепочки; сначала проверьте сохранённые исходные настройки')
    plan = chain_plan(api, state, extra)
    clients = {}
    for before, _ in plan:
        for client in parse(before['settings']).get('clients', []):
            if client['email'] not in clients:
                snapshot = canonical_client(api, client['email'])
                client_update_payload(snapshot)
                clients[client['email']] = snapshot
    backup = Path(state.get('backup_dir', '/root/selfsteal-3xui/backups')) / ('chain-' + time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '-' + secrets.token_hex(3)) / 'panel-before.json'
    journal = {'before': [copy.deepcopy(before) for before, _ in plan], 'backup': str(backup),
               'new_id': extra['id'] if extra else None, 'clients': list(clients.values())}
    secure_json(backup, journal)
    state['last_chain_backup'] = str(backup)
    state['pending_chain'] = journal
    save()
    try:
        for _, after in reversed(plan):
            api.call('panel/api/inbounds/update/%s' % after['id'], payload(after))
        current = {row['id']: row for row in api.list()}
        for before, after in plan:
            actual = current[after['id']]
            if (parse(actual['streamSettings']) != parse(after['streamSettings'])
                    or parse(actual['settings']) != parse(before['settings'])):
                raise RuntimeError('Панель не подтвердила цепочку или сохранила другие параметры клиентов')
        for snapshot in clients.values():
            check_client_binding(api, snapshot, snapshot.get('inboundIds') or [])
        api.restart()
        wait_chain_runtime(state, [(before, current[after['id']]) for before, after in plan])
    except Exception:
        restore_chain(api, state, save)
        raise


def repair_chain(state, save):
    if state.get('reality_mode') == 'parallel':
        raise RuntimeError('В параллельном режиме цепочка не используется; восстановление отменено')
    if state.get('removed') or state.get('pending_add_inbound') or state.get('pending_chain'):
        raise RuntimeError('Установка удалена или есть незавершённая операция; сначала проверьте сохранённое состояние')
    require_version(state)
    api = API(state)
    apply_chain(api, state, save)
    state['reality_chain'] = True
    state.pop('pending_chain', None)
    save()
    ports = [443] + [record['port'] for record in state.get('added_inbounds') or []] + [state.get('target_port', 9443)]
    print('Цепочка Reality: ' + ' -> '.join(map(str, ports)))
    print('Между inbound: xver 0. Перед nginx: xver 1. Fingerprint: firefox.')
    print('Ключи, пользователи и panel/hosts сохранены. Обновите подписку в приложении.')


def inbound_uses_udp(row):
    protocol = str(row.get('protocol') or '').lower()
    if protocol in ('hysteria', 'tuic', 'wireguard', 'amneziawg'):
        return True
    stream = parse(row.get('streamSettings') or row.get('stream_settings') or {})
    return stream.get('network') in ('hysteria', 'kcp', 'quic')


def add_hysteria(state, port, domain, salamander, save):
    # Independent UDP Hysteria 2: it never changes the Reality TCP chain.
    if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
        raise RuntimeError('Порт должен быть от 1 до 65535')
    if (not re.fullmatch(r'(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', domain)
            or len(domain) > 253):
        raise RuntimeError('Некорректный домен: нужен ASCII/Punycode')
    if state.get('removed') or any(state.get(k) for k in ('pending_hysteria', 'pending_add_inbound', 'pending_chain')):
        raise RuntimeError('Установка удалена или есть незавершённая операция')
    if not all(state.get(k) for k in ('domain', 'panel_url', 'panel_username', 'panel_password', 'inbound_id')):
        raise RuntimeError('Сначала установите и настройте Self-Steal')
    cert = Path('/etc/letsencrypt/live') / domain / 'fullchain.pem'
    key = Path('/etc/letsencrypt/live') / domain / 'privkey.pem'
    if not cert.is_file() or not key.is_file():
        raise RuntimeError("Не найден сертификат Let\'s Encrypt для " + domain + '. Выпустите его через certbot.')
    checks = (
        (['openssl', 'x509', '-in', str(cert), '-noout', '-checkend', '3600'], None),
        (['openssl', 'x509', '-in', str(cert), '-noout', '-checkhost', domain], 'does match certificate'),
        (['openssl', 'pkey', '-in', str(key), '-noout'], None),
    )
    for cmd, required in checks:
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=12)
        except (OSError, subprocess.TimeoutExpired):
            raise RuntimeError('Не удалось проверить TLS-сертификат или ключ') from None
        if result.returncode or (required and required not in result.stdout):
            raise RuntimeError('Сертификат не подходит для домена, истёк или ключ недоступен')

    # Verify the existing Reality configuration before changing the panel.
    api, _ = verify(state)
    if any(not row.get('nodeId') and int(row.get('port') or 0) == port
           and inbound_uses_udp(row) for row in api.list()):
        raise RuntimeError('UDP-порт уже назначен существующему inbound')
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.bind(('0.0.0.0', port))
    except OSError:
        raise RuntimeError('UDP-порт занят другим процессом') from None
    finally:
        probe.close()

    auth = secrets.token_hex(24)
    obfs_password = secrets.token_urlsafe(24) if salamander else ''
    email = 'selfsteal-hy-' + secrets.token_hex(6)
    tag = 'selfsteal-hysteria-%d-%s' % (port, secrets.token_hex(4))
    settings = {'version': 2, 'clients': [{
        'auth': auth, 'email': email, 'limitIp': 0, 'totalGB': 0, 'expiryTime': 0,
        'enable': True, 'tgId': 0, 'subId': secrets.token_hex(8), 'comment': '', 'reset': 0,
    }]}
    stream = {
        'network': 'hysteria', 'hysteriaSettings': {'version': 2, 'udpIdleTimeout': 60},
        'security': 'tls', 'tlsSettings': {
            'serverName': domain, 'minVersion': '1.2', 'maxVersion': '1.3',
            'rejectUnknownSni': False, 'alpn': ['h3'],
            'certificates': [{
                'certificateFile': str(cert), 'keyFile': str(key),
                'usage': 'encipherment', 'oneTimeLoading': False, 'buildChain': False,
                'useFile': True,
            }],
        },
    }
    if salamander:
        stream['finalmask'] = {'udp': [{'type': 'salamander',
                                       'settings': {'password': obfs_password}}]}
    inbound = {
        'remark': 'selfsteal-hysteria-%d' % port, 'enable': True, 'expiryTime': 0,
        'total': 0, 'up': 0, 'down': 0, 'port': port,
        'protocol': 'hysteria', 'listen': '0.0.0.0',
        'tag': tag, 'trafficReset': 'never', 'trafficResetDay': 1,
        'sniffing': json.dumps({'enabled': False}), 'settings': json.dumps(settings),
        'streamSettings': json.dumps(stream), 'shareAddrStrategy': 'custom',
        'shareAddr': domain, 'disableFlow': False,
    }
    state['pending_hysteria'] = {'port': port, 'tag': tag, 'domain': domain}
    save()
    created_id = None
    try:
        created = api.call('panel/api/inbounds/add', inbound)
        if not isinstance(created, dict) or created.get('id') is None:
            raise RuntimeError('Панель не вернула ID нового Hysteria inbound')
        created_id = int(created['id'])
        state['pending_hysteria']['id'] = created_id
        save()
        stored = [r for r in api.list() if r.get('tag') == tag and int(r.get('port') or 0) == port]
        if len(stored) != 1 or int(stored[0]['id']) != created_id or stored[0]['protocol'] != 'hysteria':
            raise RuntimeError('API панели не подтвердил созданный Hysteria inbound')
        actual_settings = parse(stored[0].get('settings') or {})
        actual_stream = parse(stored[0].get('streamSettings') or {})
        actual_clients = actual_settings.get('clients') or []
        actual_masks = (actual_stream.get('finalmask') or {}).get('udp') or []
        if (actual_settings.get('version') != 2
                or not any(c.get('auth') == auth and c.get('email') == email for c in actual_clients)
                or actual_stream.get('network') != 'hysteria'
                or actual_stream.get('security') != 'tls'
                or (salamander and not any(m.get('type') == 'salamander'
                    and m.get('settings', {}).get('password') == obfs_password
                    for m in actual_masks))):
            raise RuntimeError('Панель изменила параметры Hysteria: операция отменена')

        api.restart()
        runtime_path = Path(state.get('runtime_config') or str(
            Path(state['panel_binary']).parent / 'bin/config.json'))
        verified = False
        for _ in range(25):
            try:
                runtime = json.loads(runtime_path.read_text())
                live = [r for r in runtime.get('inbounds', [])
                        if r.get('tag') == tag and r.get('protocol') == 'hysteria'
                        and int(r.get('port') or 0) == port]
                if len(live) == 1:
                    rt_stream = live[0].get('streamSettings') or {}
                    rt_settings = live[0].get('settings') or {}
                    rt_clients = rt_settings.get('clients') or rt_settings.get('users') or []
                    rt_masks = (rt_stream.get('finalmask') or {}).get('udp') or []
                    verified = (
                        rt_stream.get('network') == 'hysteria'
                        and rt_stream.get('security') == 'tls'
                        and any(c.get('auth') == auth for c in rt_clients)
                        and (not salamander or any(m.get('type') == 'salamander'
                            and m.get('settings', {}).get('password') == obfs_password
                            for m in rt_masks)))
                if verified:
                    listener = subprocess.run(['ss', '-H', '-lunp', 'sport = :%d' % port],
                                              capture_output=True, text=True, timeout=3)
                    verified = listener.returncode == 0 and 'xray' in listener.stdout.lower()
            except (OSError, ValueError, TypeError, KeyError, subprocess.TimeoutExpired):
                verified = False
            if verified:
                break
            time.sleep(1)
        if not verified:
            raise RuntimeError('Xray не подтвердил запуск Hysteria 2 и прослушивание UDP')

        uri = 'hysteria2://%s@%s:%d/?sni=%s&insecure=0' % (
            urllib.parse.quote(auth, safe=''), domain, port,
            urllib.parse.quote(domain, safe=''))
        if salamander:
            uri += '&obfs=salamander&obfs-password=' + urllib.parse.quote(obfs_password, safe='')
        uri += '#' + urllib.parse.quote('selfsteal-hysteria-%d' % port, safe='')
        folder = Path('/root/selfsteal-3xui/hysteria')
        folder.mkdir(parents=True, mode=0o700, exist_ok=True)
        credential_file = folder / ('inbound-%d-%d.json' % (port, created_id))
        secure_json(credential_file, {'id': created_id, 'domain': domain, 'port': port,
                                      'email': email, 'auth': auth,
                                      'salamander_password': obfs_password, 'uri': uri})
        state.setdefault('hysteria_inbounds', []).append({
            'id': created_id, 'port': port, 'tag': tag,
            'domain': domain, 'credential_file': str(credential_file),
        })
        state.pop('pending_hysteria', None)
        save()
        print('Hysteria 2 создана: inbound ID %d, UDP %d, TLS %s.' % (created_id, port, domain))
        print('Salamander: ' + ('включён' if salamander else 'выключен'))
        print('Ссылка клиента: ' + uri)
        print('Закрытая копия реквизитов: ' + str(credential_file))
        print('TCP Reality и его цепочка не изменены.')
        print('Проверьте доступность UDP %d в UFW и файрволе провайдера.' % port)
    except Exception:
        failures = []
        try:
            owned = [r for r in api.list()
                     if r.get('tag') == tag and r.get('protocol') == 'hysteria'
                     and int(r.get('port') or 0) == port]
            if len(owned) > 1:
                raise RuntimeError('Обнаружены дубликаты нового inbound')
            for row in owned:
                api.call('panel/api/inbounds/del/%s' % int(row['id']), {})
            if owned or created_id is not None:
                api.restart()
            if any(r.get('tag') == tag for r in api.list()):
                raise RuntimeError('Не удалось подтвердить удаление')
        except Exception:
            failures.append('inbound/Xray')
        if failures:
            state['pending_hysteria']['rollback_incomplete'] = failures
            save()
            raise RuntimeError('Откат Hysteria не завершён. Проверьте записи в 3x-ui.') from None
        state.pop('pending_hysteria', None)
        save()
        raise


def add_inbound(state, port, save, sni=None):
    if state.get('reality_mode') == 'parallel':
        return parallel_add_inbound(state, port, sni, save)
    if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
        raise RuntimeError('Порт должен быть целым числом от 1 до 65535')
    if state.get('removed'):
        raise RuntimeError('Установка отмечена как удалённая; сначала выполните установку снова')
    if state.get('pending_add_inbound', {}).get('rollback_incomplete'):
        raise RuntimeError('Предыдущий откат не завершён; сначала проверьте сохранённые сведения об inbound и пользователе в панели')
    if state.get('pending_chain'):
        raise RuntimeError('Есть незавершённое изменение цепочки; проверьте сохранённое состояние')
    domain = state.get('domain', '')
    if not domain or not state.get('panel_username') or not state.get('panel_password'):
        raise RuntimeError('В сохранённом состоянии нет домена или данных входа в панель')

    # Verify the managed 443 Reality inbound and the running Xray configuration
    # before adding anything. This protects unrelated or incomplete panel setups.
    api, _ = verify(state)
    inbounds = api.list()
    if any(not item.get('nodeId') and int(item.get('port') or 0) == port
           and not inbound_uses_udp(item) for item in inbounds):
        raise RuntimeError('Этот TCP-порт уже назначен существующему inbound')
    if any(item.get('tag') == 'selfsteal-reality-%d' % port for item in inbounds):
        raise RuntimeError('Inbound с таким служебным тегом уже существует')

    # Detect listeners that are not represented by a local 3x-ui inbound.
    sockets = []
    try:
        for family, address in ((socket.AF_INET, ('0.0.0.0', port)),
                                (socket.AF_INET6, ('::', port))):
            try:
                sock = socket.socket(family, socket.SOCK_STREAM)
            except OSError:
                if family == socket.AF_INET:
                    raise
                continue
            sockets.append(sock)
            if family == socket.AF_INET6:
                sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            sock.bind(address)
    except OSError:
        raise RuntimeError('TCP-порт уже занят локальным процессом') from None
    finally:
        for sock in sockets:
            sock.close()

    base = next((item for item in inbounds if int(item.get('id') or 0) == int(state['inbound_id'])), None)
    if not base:
        raise RuntimeError('Управляемый inbound на 443 не найден в панели')
    base_stream = parse(base.get('streamSettings') or {})
    if base_stream.get('security') != 'reality' or base_stream.get('network') not in ('tcp', 'raw'):
        raise RuntimeError('Существующий inbound на 443 несовместим с Reality/TCP')

    client_snapshot = choose_existing_client(api)
    client_email = client_snapshot['client']['email']
    client_uuid = client_snapshot['client']['uuid']
    original_client_ids = set(client_snapshot.get('inboundIds') or [])

    tag = 'selfsteal-reality-%d' % port
    host_remark = 'selfsteal-%d-to-443' % port
    live_ids = {int(item.get('id') or 0) for item in inbounds}
    host_groups = api.call('panel/api/hosts/list') or []
    stale_groups = []
    for group in host_groups:
        try:
            ids = [int(value) for value in group.get('inboundIds') or []]
            same_record = (group.get('remark') == host_remark
                           and host_group_has_address(group, domain)
                           and int(group.get('port') or 0) == 443)
        except (TypeError, ValueError):
            continue
        if same_record and ids and not any(value in live_ids for value in ids):
            group_id = str(group.get('groupId') or '')
            if not group_id:
                raise RuntimeError('Найдена старая запись panel/hosts без ID; удалите её в панели вручную')
            stale_groups.append(group_id)
    for old_group_id in stale_groups:
        api.call('panel/api/hosts/bulk/del', {'ids': [old_group_id]})
    if stale_groups:
        print('Удалена старая незавершённая запись panel/hosts для порта %d.' % port)

    private = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip('=')
    short_id = secrets.token_hex(8)
    target = '127.0.0.1:%d' % int(state.get('target_port', 9443))
    reality = {
        'show': False,
        'target': target,
        'serverNames': [domain],
        'privateKey': private,
        'shortIds': [short_id],
        'xver': 1,
        'settings': {
            'publicKey': public_key(private),
            'fingerprint': 'firefox',
            'serverName': domain,
            'spiderX': '/',
        },
    }
    inbound = {
        'remark': 'selfsteal-reality-%d' % port,
        'enable': True,
        'expiryTime': 0,
        'total': 0,
        'up': 0,
        'down': 0,
        'port': port,
        'protocol': 'vless',
        'listen': '',
        'tag': tag,
        'trafficReset': 'never',
        'trafficResetDay': 1,
        'sniffing': json.dumps({'enabled': True, 'destOverride': ['http', 'tls', 'quic'], 'routeOnly': True}),
        'settings': json.dumps({'clients': [], 'decryption': 'none', 'fallbacks': []}),
        'streamSettings': json.dumps({
            'network': 'tcp',
            'security': 'reality',
            'realitySettings': reality,
            'tcpSettings': {'header': {'type': 'none'}},
        }),
        'shareAddrStrategy': 'custom',
        'shareAddr': domain,
        'disableFlow': False,
    }
    host_payload = {
        'inboundIds': [],
        'remark': host_remark,
        'hosts': [domain],
        'port': 443,
        'security': 'same',
        'sni': '',
        'hostHeader': '',
        'path': '',
        'alpn': [],
        'isDisabled': False,
        'isHidden': False,
        'tags': [],
    }

    created_id = None
    group_id = None
    previous_added = copy.deepcopy(state.get('added_inbounds') or [])
    previous_chain = state.get('reality_chain')
    state['pending_add_inbound'] = {'port': port, 'tag': tag, 'remark': host_remark,
                                    'client_email': client_email, 'client_uuid': client_uuid,
                                    'original_client_inbound_ids': sorted(original_client_ids)}
    save()
    try:
        created = api.call('panel/api/inbounds/add', inbound)
        if isinstance(created, dict) and created.get('id') is not None:
            created_id = int(created['id'])
            state['pending_add_inbound']['id'] = created_id
            save()
        else:
            raise RuntimeError('Панель не вернула ID созданного inbound')

        host_payload['inboundIds'] = [created_id]
        api.call('panel/api/hosts/add', host_payload)
        groups = api.call('panel/api/hosts/list') or []
        matches = [group for group in groups
                   if group.get('inboundIds') == [created_id]
                   and group.get('remark') == host_remark
                   and host_group_has_address(group, domain)
                   and int(group.get('port') or 0) == 443]
        if len(matches) != 1 or not matches[0].get('groupId'):
            raise RuntimeError('Запись panel/hosts не удалось подтвердить через API')
        group_id = str(matches[0]['groupId'])

        check_client_binding(api, client_snapshot, original_client_ids)
        api.call('panel/api/clients/%s/attach' % urllib.parse.quote(client_email, safe=''),
                 {'inboundIds': [created_id]})
        attached = check_client_binding(api, client_snapshot, original_client_ids | {created_id})
        added_inbound = next((item for item in api.list() if item.get('id') == created_id), None)
        added_clients = parse(added_inbound['settings']).get('clients', []) if added_inbound else []
        if (len(added_clients) != 1 or added_clients[0].get('id') != client_uuid
                or added_clients[0].get('email') != client_email
                or added_clients[0].get('flow', '') != client_snapshot['client'].get('flow', '')):
            raise RuntimeError('Новый inbound не подтвердил выбранного пользователя')
        selected_client = added_clients[0]
        traffic_limit = attached['client'].get('totalGB') or 0
        active = (client_active(selected_client, added_inbound)
                  and (not traffic_limit or (attached.get('usedTraffic') or 0) < traffic_limit))
        expected_clients = {(client_uuid, selected_client.get('flow', ''))} if active else set()

        apply_chain(api, state, save, extra=added_inbound)
        runtime_path = Path(state.get('runtime_config', str(Path(state['panel_binary']).parent / 'bin/config.json')))
        runtime_ready = False
        listener_ready = False
        for _ in range(30):
            try:
                runtime = json.loads(runtime_path.read_text())
                rows = [row for row in runtime.get('inbounds', [])
                        if row.get('port') == port and row.get('tag') == tag]
                if len(rows) == 1:
                    row = rows[0]
                    rs = row.get('streamSettings', {}).get('realitySettings', {})
                    runtime_ready = (
                        row.get('protocol') == 'vless'
                        and len(row.get('settings', {}).get('clients', [])) == len(expected_clients)
                        and {(client.get('id'), client.get('flow', ''))
                             for client in row.get('settings', {}).get('clients', [])} == expected_clients
                        and rs.get('target', rs.get('dest')) == target
                        and rs.get('privateKey') == private
                        and rs.get('shortIds') == [short_id]
                        and rs.get('serverNames') == [domain]
                    )
            except (OSError, ValueError, AttributeError):
                runtime_ready = False
            if runtime_ready:
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=0.4):
                        listener_ready = True
                except OSError:
                    listener_ready = False
            if runtime_ready and listener_ready:
                break
            time.sleep(1)
        if not runtime_ready or not listener_ready:
            raise RuntimeError('Xray не подтвердил запуск нового inbound на выбранном порту')

        state.setdefault('added_inbounds', []).append({
            'id': created_id,
            'port': port,
            'tag': tag,
            'host_group_id': group_id,
            'address': domain,
            'host_port': 443,
            'client_email': client_email,
            'client_uuid': client_uuid,
        })
        state.pop('pending_add_inbound', None)
        state.pop('pending_chain', None)
        state['reality_chain'] = True
        save()
        print('Добавлен inbound: ID %s, TCP-порт %d.' % (created_id, port))
        print('panel/hosts: inbound ID %s, адрес %s, порт 443.' % (created_id, domain))
        print('Пользователь: %s; inbound добавлен в его существующую подписку.' % terminal_label(client_email))
        if not active:
            print('Пользователь неактивен или исчерпал лимит; привязка сохранена, доступ остаётся ограниченным.')
        ports = [443] + [record['port'] for record in state['added_inbounds']] + [state.get('target_port', 9443)]
        print('Цепочка Reality: ' + ' -> '.join(map(str, ports)))
    except Exception:
        rollback_errors = []
        state['added_inbounds'] = previous_added
        if previous_chain is None:
            state.pop('reality_chain', None)
        else:
            state['reality_chain'] = previous_chain
        owned_id = created_id
        restart_needed = created_id is not None
        try:
            restore_chain(api, state, save)
            current_inbounds = api.list()
            candidates = [item for item in current_inbounds
                          if item.get('tag') == tag
                          and int(item.get('port') or 0) == port
                          and parse(item.get('streamSettings') or {}).get('realitySettings', {}).get('privateKey') == private]
            if len(candidates) > 1:
                raise RuntimeError('duplicate owned inbounds')
            if candidates:
                owned_id = int(candidates[0]['id'])
                current_client = canonical_client(api, client_email)
                if current_client['client'].get('uuid') != client_uuid:
                    raise RuntimeError('Идентификатор пользователя изменился; автоматический откат отменён')
                if owned_id in (current_client.get('inboundIds') or []):
                    api.call('panel/api/clients/%s/detach' % urllib.parse.quote(client_email, safe=''),
                             {'inboundIds': [owned_id]})
                api.call('panel/api/inbounds/del/%s' % owned_id, {})
                restart_needed = True
                check_client_binding(api, client_snapshot, original_client_ids)
        except Exception:
            rollback_errors.append('inbound')
        try:
            current_groups = api.call('panel/api/hosts/list') or []
            candidates = [group for group in current_groups
                          if owned_id is not None
                          and group.get('inboundIds') == [owned_id]
                          and group.get('remark') == host_remark
                          and host_group_has_address(group, domain)
                          and int(group.get('port') or 0) == 443]
            for group in candidates:
                gid = str(group.get('groupId') or '')
                if gid:
                    api.call('panel/api/hosts/bulk/del', {'ids': [gid]})
        except Exception:
            rollback_errors.append('panel/hosts')
        if restart_needed:
            try:
                api.restart()
            except Exception:
                rollback_errors.append('Xray restart')
        if rollback_errors:
            state['pending_add_inbound'] = {
                'id': created_id,
                'port': port,
                'tag': tag,
                'remark': host_remark,
                'host_group_id': group_id,
                'client_email': client_email,
                'client_uuid': client_uuid,
                'original_client_inbound_ids': sorted(original_client_ids),
                'rollback_incomplete': rollback_errors,
            }
            save()
            raise RuntimeError('Не удалось полностью откатить операцию (%s); сохранено состояние для проверки панели' % ', '.join(rollback_errors)) from None
        state.pop('pending_add_inbound', None)
        save()
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
                raise RuntimeError('Принадлежность созданного клиента изменилась; удаление при откате отменено')
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
        raise RuntimeError('Нет активного клиента для экспорта и проверки подключения')
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
    raise RuntimeError('Генератор ссылок панели не вернул требуемые параметры домена, Vision и Reality; искусственный экспорт отменен')


def verify(state):
    require_version(state)
    if state.get('reality_mode') == 'parallel':
        api = API(state)
        records = parallel_existing_rows(state, api)
        parallel_runtime(state, records)
        parallel_probe_443(records)
        checked_uri(api, state, records[0]['before'])
        return api, records[0]['before']
    api = API(state)
    inbound = pick(api.list())
    if not inbound or inbound['id'] != state.get('inbound_id'):
        raise RuntimeError('Настроенное локальное входящее подключение на порту 443 не найдено')
    stream = parse(inbound['streamSettings'])
    reality = stream['realitySettings']
    target, primary_xver = chain_primary_endpoint(state)
    if stream.get('network') != 'tcp' or reality.get('target') != target or reality.get('xver', 0) != primary_xver or reality.get('serverNames') != [state['domain']] or inbound.get('shareAddrStrategy') != 'custom' or inbound.get('shareAddr') != state['domain']:
        raise RuntimeError('Проверка конфигурации Reality через API панели не пройдена')
    if state.get('reality_chain'):
        plan = chain_plan(api, state)
        for before, after in plan:
            if parse(before['streamSettings']) != parse(after['streamSettings']):
                raise RuntimeError('Цепочка Reality изменена; восстановите её через пункт 5')
        wait_chain_runtime(state, plan)
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
                if rs.get('target', rs.get('dest')) == target and rs.get('privateKey') == reality['privateKey'] and rs.get('shortIds') == reality['shortIds'] and rs.get('serverNames') == [state['domain']] and rs.get('xver', 0) == primary_xver:
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
        raise RuntimeError('Конфигурация, используемая встроенным Xray, не совпадает с сохраненными идентификаторами API')
    if not state.get('is_existing'):
        settings = api.call('panel/api/setting/all', {})
        if settings.get('webListen') != '127.0.0.1' or any(settings.get(k) for k in ('subEnable', 'subJsonEnable', 'subClashEnable')):
            raise RuntimeError('Проверка безопасности адресов панели и подписок новой установки не пройдена')
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
        'public_panel_enabled': (None if state.get('is_existing') and state.get('panel_route_status') == 'disabled-custom-routes-preserved' else bool(state.get('public_url'))),
        'public_url': state.get('public_url'),
        'public_panel_status': state.get('panel_route_status', 'disabled'),
        'script_exposed_public_admin': state.get('script_exposed_public_admin', False),
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



# Parallel Reality (opt-in): SNI preread routes independently to localhost.
# The first inbound keeps its old public address/SNI; each extra inbound needs
# an independent hostname. Backups contain secrets and are never printed.
PARALLEL_HEADER = '# Managed by selfsteal-3xui parallel; do not edit manually.\n'
PARALLEL_STREAM = Path('/etc/nginx/modules-enabled/99-selfsteal-3xui-stream.conf')
PARALLEL_TLS = Path('/etc/nginx/conf.d/99-selfsteal-3xui-parallel-tls.conf')
PARALLEL_ACME = Path('/etc/nginx/sites-enabled/99-selfsteal-3xui-parallel-acme.conf')


def parallel_validate_sni(value):
    if not isinstance(value, str):
        raise RuntimeError('SNI должен быть строкой')
    value = value.lower().strip().rstrip('.')
    if (len(value) > 253 or not re.fullmatch(
            r'(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', value)):
        raise RuntimeError('Некорректный SNI: нужен домен ASCII/Punycode')
    return value


def parallel_cert_valid(sni):
    cert = Path('/etc/letsencrypt/live') / sni / 'fullchain.pem'
    key = cert.parent / 'privkey.pem'
    if not cert.is_file() or not key.is_file():
        return False
    try:
        test = subprocess.run(['openssl', 'x509', '-in', str(cert), '-noout',
                               '-checkhost', sni], capture_output=True, text=True,
                              timeout=8)
        expires = subprocess.run(['openssl', 'x509', '-in', str(cert), '-noout',
                                  '-checkend', '86400'], capture_output=True,
                                 text=True, timeout=8)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return (test.returncode == 0 and 'does match certificate' in test.stdout
            and expires.returncode == 0)


def parallel_dns_check(sni, main):
    try:
        src = {x[4][0] for x in socket.getaddrinfo(main, 443, type=socket.SOCK_STREAM)}
        dst = {x[4][0] for x in socket.getaddrinfo(sni, 443, type=socket.SOCK_STREAM)}
    except OSError:
        raise RuntimeError('DNS для ' + sni + ' не отвечает') from None
    if not src or not dst or not dst.issubset(src):
        raise RuntimeError('DNS для ' + sni + ' не совпадает с адресами основного домена')


def parallel_preconditions(state, mapping, api):
    if state.get('removed') or state.get('pending_chain') or state.get('pending_add_inbound') or state.get('pending_hysteria'):
        raise RuntimeError('Есть незавершённая операция: миграция отменена')
    if state.get('reality_mode') == 'parallel':
        raise RuntimeError('Сервер уже работает в параллельном режиме')
    require_version(state)
    if not state.get('inbound_id') or not state.get('domain'):
        raise RuntimeError('Нет управляемого Reality inbound или домена')
    records = [{'id': state['inbound_id'], 'port': 443, 'sni': state['domain']}]
    for old in state.get('added_inbounds') or []:
        ident = str(old['id'])
        if ident not in mapping:
            raise RuntimeError('Не задан новый SNI для inbound ID ' + ident)
        records.append({'id': int(old['id']), 'port': int(old['port']),
                        'sni': parallel_validate_sni(mapping[ident])})
    if set(mapping) != {str(r['id']) for r in records[1:]}:
        raise RuntimeError('Список SNI не соответствует сохранённым inbound')
    snis = [parallel_validate_sni(r['sni']) for r in records]
    if len(set(snis)) != len(snis):
        raise RuntimeError('У каждого Reality должен быть собственный SNI')
    if len(set(r['port'] for r in records)) != len(records):
        raise RuntimeError('Найдены повторяющиеся TCP-порты')
    # Existing chain is checked before modification. Never migrate an unknown
    # hand-edited deployment whose target or clients cannot be validated.
    if state.get('reality_chain') and len(records) > 1:
        for before, expected in chain_plan(api, state):
            if parse(before['streamSettings']) != parse(expected['streamSettings']):
                raise RuntimeError('Исходная Reality-цепочка изменена; сначала восстановите её')
    by_id = {int(row['id']): row for row in api.list()}
    for r in records:
        row = by_id.get(int(r['id']))
        if (not row or row.get('protocol') != 'vless'
                or int(row.get('port') or 0) != r['port']
                or parse(row.get('streamSettings') or {}).get('security') != 'reality'):
            raise RuntimeError('Невозможно безопасно сопоставить inbound ID ' + str(r['id']))
        r['before'] = copy.deepcopy(row)
    return records


def parallel_pick_port(existing):
    busy = {int(p) for p in existing}
    listeners = subprocess.run(['ss', '-H', '-ltn'], capture_output=True, text=True,
                               timeout=5, check=True).stdout
    for line in listeners.splitlines():
        addr = line.split()
        if len(addr) >= 4:
            try:
                busy.add(int(addr[3].rsplit(':', 1)[1]))
            except (ValueError, IndexError):
                pass
    for port in range(10443, 10550):
        if port not in busy:
            return port
    raise RuntimeError('Нет свободного внутреннего TCP-порта для первого Reality')


def parallel_texts(state, records):
    main = parallel_validate_sni(state['domain'])
    root = Path('/var/www/selfsteal-3xui-' + main)
    if not root.is_dir() or not (root / 'index.html').is_file():
        raise RuntimeError('Не найден управляемый HTTPS-сайт заглушки; ручной nginx не перезаписывается')
    extras = [r for r in records if r['sni'] != main]
    mapping = [
        '    ' + r['sni'] + ' 127.0.0.1:' + str(r['port']) + ';'
        for r in records
    ]
    stream = (PARALLEL_HEADER + 'stream {\n'
              '    map $ssl_preread_server_name $selfsteal_parallel_backend {\n'
              + '\n'.join(mapping) + '\n'
              '        default 127.0.0.1:9443;\n'
              '    }\n'
              '    server {\n'
              '        listen 443;\n'
              '        listen [::]:443;\n'
              '        ssl_preread on;\n'
              '        proxy_protocol on;\n'
              '        proxy_pass $selfsteal_parallel_backend;\n'
              '        proxy_connect_timeout 5s;\n'
              '        proxy_timeout 1h;\n'
              '    }\n'
              '}\n')
    tls = PARALLEL_HEADER
    acme = PARALLEL_HEADER
    for r in extras:
        name = r['sni']
        cert = '/etc/letsencrypt/live/' + name
        tls += (
            'server {\n'
            '    listen 127.0.0.1:9443 ssl http2 proxy_protocol;\n'
            '    server_name ' + name + ';\n'
            '    ssl_certificate ' + cert + '/fullchain.pem;\n'
            '    ssl_certificate_key ' + cert + '/privkey.pem;\n'
            '    ssl_protocols TLSv1.3;\n'
            '    set_real_ip_from 127.0.0.1;\n'
            '    real_ip_header proxy_protocol;\n'
            '    root ' + str(root) + ';\n'
            '    location / { try_files $uri $uri/ =404; }\n'
            '}\n')
        acme += (
            'server {\n'
            '    listen 80;\n'
            '    listen [::]:80;\n'
            '    server_name ' + name + ';\n'
            '    location ^~ /.well-known/acme-challenge/ { root ' + str(root) + '; }\n'
            '    location / { return 301 https://$host$request_uri; }\n'
            '}\n')
    return {PARALLEL_STREAM: stream, PARALLEL_TLS: tls, PARALLEL_ACME: acme}, root


def parallel_backup_files(paths):
    data = {}
    for path in paths:
        if path.is_symlink() or (path.exists() and not path.is_file()):
            raise RuntimeError('Конфликт пути nginx: ' + str(path))
        if path.is_file() and not path.read_text().startswith(PARALLEL_HEADER):
            raise RuntimeError('Существующий nginx файл не принадлежит Self-Steal: ' + str(path))
        data[str(path)] = (dict(exists=True,
                                content=base64.b64encode(path.read_bytes()).decode(),
                                mode=path.stat().st_mode & 0o777)
                           if path.is_file() else dict(exists=False))
    return data


def parallel_write_file(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.tmp-' + secrets.token_hex(6))
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as out:
        out.write(data)
        out.flush()
        os.fsync(out.fileno())
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def parallel_restore_files(files):
    for name, entry in files.items():
        path = Path(name)
        if not path.exists() and not entry['exists']:
            continue
        if path.is_symlink():
            raise RuntimeError('Путь nginx изменился на символьную ссылку: ' + name)
        if entry['exists']:
            parallel_write_file(path, base64.b64decode(entry['content']))
            os.chmod(path, entry['mode'])
        else:
            if path.is_file():
                path.unlink()


def parallel_nginx(action='reload'):
    tested = subprocess.run(['nginx', '-t'], capture_output=True, text=True,
                            timeout=12)
    if tested.returncode:
        raise RuntimeError('nginx -t не принял подготовленную конфигурацию')
    subprocess.run(['systemctl', action, 'nginx'], check=True,
                   capture_output=True, timeout=25)


def parallel_ensure_certs(state, records, texts, root):
    # To obtain certificates without taking the existing 443 listener offline,
    # add a temporary (then retained for renewal) HTTP-01 virtual host.
    parallel_write_file(PARALLEL_ACME, texts[PARALLEL_ACME].encode())
    parallel_nginx()
    for r in records[1:]:
        sni = r['sni']
        if parallel_cert_valid(sni):
            continue
        cmd = ['certbot', 'certonly', '--webroot', '-w', str(root),
               '--non-interactive', '--agree-tos',
               '--register-unsafely-without-email',
               '--keep-until-expiring', '-d', sni]
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
        except (OSError, subprocess.TimeoutExpired):
            raise RuntimeError('Не удалось выпустить сертификат для ' + sni) from None
        if p.returncode or not parallel_cert_valid(sni):
            raise RuntimeError('Не удалось проверить сертификат ' + sni
                               + '; проверьте DNS, TCP 80 и certbot')


def parallel_runtime(state, records):
    path = Path(state.get('runtime_config') or str(
        Path(state['panel_binary']).parent / 'bin/config.json'))
    for _ in range(30):
        try:
            config = json.loads(path.read_text())
            live = config.get('inbounds') or []
            for r in records:
                rows = [x for x in live if x.get('tag') == r['before']['tag']
                        and int(x.get('port') or 0) == int(r['port'])]
                if len(rows) != 1 or rows[0].get('protocol') != 'vless':
                    raise ValueError('runtime row is missing')
                rt = rows[0].get('streamSettings') or {}
                configured = parse(r['after']['streamSettings'])
                expected = configured['realitySettings']
                live_reality = rt.get('realitySettings') or {}
                if (live_reality.get('privateKey') != expected['privateKey']
                        or live_reality.get('shortIds') != expected['shortIds']
                        or live_reality.get('serverNames') != [r['sni']]
                        or (live_reality.get('target') or live_reality.get('dest')) != expected['target']
                        or not (rt.get('tcpSettings') or {}).get('acceptProxyProtocol')):
                    raise ValueError('runtime does not match')
            return
        except (OSError, ValueError, KeyError, TypeError):
            time.sleep(1)
    raise RuntimeError('Xray не подтвердил работу независимых inbound')


def parallel_probe_443(records):
    context = ssl.create_default_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    for r in records:
        try:
            with socket.create_connection(('127.0.0.1', 443), timeout=8) as raw:
                raw.settimeout(8)
                with context.wrap_socket(raw, server_hostname=r['sni']) as tls:
                    tls.sendall(('HEAD / HTTP/1.1\r\nHost: ' + r['sni']
                                 + '\r\nConnection: close\r\n\r\n').encode())
                    line = tls.recv(512).split(b'\r\n', 1)[0]
                    if not re.match(rb'^HTTP/1\.[01] [2345]\d\d', line):
                        raise RuntimeError('Необычный HTTP-ответ через Reality')
        except (OSError, ssl.SSLError) as exc:
            raise RuntimeError('Локальный HTTPS fallback недоступен для ' + r['sni']) from exc


def parallel_host_payload(row, inbound_id, sni):
    # Existing groupId remains unchanged with the documented update API.
    fields = ('inboundIds', 'remark', 'hosts', 'port', 'security', 'sni',
              'hostHeader', 'path', 'alpn', 'isDisabled', 'isHidden', 'tags')
    if row:
        result = {key: copy.deepcopy(row[key]) for key in fields if key in row}
    else:
        result = dict(remark='selfsteal-parallel-443', alpn=[], tags=[],
                      isDisabled=False, isHidden=False, security='same')
    result.update(inboundIds=[int(inbound_id)], hosts=[sni], port=443,
                  security='same', sni=sni)
    return result


def parallel_host_group(api, inbound_id, groups):
    found = [g for g in groups if g.get('inboundIds') == [int(inbound_id)]]
    if len(found) > 1:
        raise RuntimeError('У inbound несколько групп hosts; автоматическая миграция отменена')
    return found[0] if found else None


def parallel_hosts_apply(api, records, old_groups):
    created = []
    for r in records:
        prior = parallel_host_group(api, int(r['id']), old_groups)
        payload_value = parallel_host_payload(prior, r['id'], r['sni'])
        if prior and prior.get('groupId'):
            api.call('panel/api/hosts/update/' + str(prior['groupId']), payload_value)
        else:
            api.call('panel/api/hosts/add', payload_value)
            updated = api.call('panel/api/hosts/list') or []
            found = [g for g in updated if g.get('inboundIds') == [int(r['id'])]
                     and g.get('hosts') == [r['sni']]]
            if len(found) != 1 or not found[0].get('groupId'):
                raise RuntimeError('Не удалось подтвердить созданную группу hosts')
            created.append(str(found[0]['groupId']))
    return created


def parallel_hosts_restore(api, records, originals):
    now = api.call('panel/api/hosts/list') or []
    for r in records:
        before = parallel_host_group(api, int(r['id']), originals)
        current = parallel_host_group(api, int(r['id']), now)
        if before and current and before.get('groupId') == current.get('groupId'):
            api.call('panel/api/hosts/update/' + str(before['groupId']),
                     parallel_host_payload_restore(before))
        elif before and not current:
            api.call('panel/api/hosts/add', parallel_host_payload_restore(before))
        elif not before and current and current.get('groupId'):
            api.call('panel/api/hosts/bulk/del', {'ids': [str(current['groupId'])]})


def parallel_host_payload_restore(group):
    allowed = ('inboundIds', 'remark', 'hosts', 'port', 'security', 'sni',
               'hostHeader', 'path', 'alpn', 'isDisabled', 'isHidden', 'tags')
    return {key: copy.deepcopy(group[key]) for key in allowed if key in group}


def parallel_restore_backup(state, api, backup, save):
    original = json.loads((backup / 'state-before.json').read_text())
    old_inbounds = json.loads((backup / 'inbounds-before.json').read_text())
    old_groups = json.loads((backup / 'hosts-before.json').read_text())
    files = json.loads((backup / 'nginx-before.json').read_text())
    # Release 443 from nginx before restarting the original Xray inbound on 443.
    parallel_restore_files(files)
    parallel_nginx()
    for old in old_inbounds:
        api.call('panel/api/inbounds/update/%s' % old['id'], payload(old))
    api.restart()
    parallel_hosts_restore(api, [{'id': x['id']} for x in old_inbounds], old_groups)
    state.clear()
    state.update(original)
    save()


def migrate_parallel(state, mapping, save):
    if state.get('pending_parallel'):
        raise RuntimeError('Есть незавершённая параллельная миграция. Сначала восстановите её.')
    api = API(state)
    records = parallel_preconditions(state, mapping, api)
    # A root module include is required before touching any live service.
    # Check for unrelated stream listeners to avoid assuming ownership of 443.
    if any((r['before'].get('listen') or '') == '::' for r in records):
        raise RuntimeError('IPv6 wildcard inbound требует ручной проверки перед миграцией')
    for r in records:
        parallel_dns_check(r['sni'], state['domain'])
    port = parallel_pick_port([x.get('port') for x in api.list()])
    records[0]['port'] = port
    for r in records:
        old = r['before']
        after = copy.deepcopy(old)
        stream = copy.deepcopy(parse(old['streamSettings']))
        reality = stream['realitySettings']
        reality.update(target='127.0.0.1:' + str(state.get('target_port', 9443)),
                       serverNames=[r['sni']], xver=1)
        reality.pop('dest', None)
        tcp = stream.setdefault('tcpSettings', {})
        tcp['acceptProxyProtocol'] = True
        after['streamSettings'] = json.dumps(stream)
        after['port'] = r['port']
        after['listen'] = '127.0.0.1'
        after['shareAddrStrategy'] = 'custom'
        after['shareAddr'] = r['sni']
        r['after'] = after
    texts, root = parallel_texts(state, records)
    if not re.search(r'(?m)^\s*include\s+/etc/nginx/modules-enabled/\*\.conf\s*;',
                     Path('/etc/nginx/nginx.conf').read_text()):
        raise RuntimeError('nginx.conf не включает modules-enabled; безопасная миграция невозможна')
    if not Path('/usr/lib/nginx/modules/ngx_stream_module.so').is_file():
        raise RuntimeError('Не установлен модуль nginx stream: sudo apt-get install libnginx-mod-stream')
    # Do not put an extra stream block behind an existing user-owned listener.
    test = subprocess.run(['nginx', '-T'], capture_output=True, text=True, timeout=12)
    if test.returncode:
        raise RuntimeError('Текущий nginx -T содержит ошибку')
    if re.search(r'\bstream\s*\{', test.stdout):
        raise RuntimeError('В nginx уже есть stream-блок: требуется ручное согласование')
    listeners = subprocess.run(['ss', '-H', '-ltnp', 'sport = :443'],
                               capture_output=True, text=True, timeout=5, check=True)
    for line in listeners.stdout.splitlines():
        if 'xray' not in line.lower():
            raise RuntimeError('TCP 443 занят посторонним listener, миграция отменена')
    for r in records[1:]:
        if parallel_host_group(api, r['id'], api.call('panel/api/hosts/list') or []) is None:
            raise RuntimeError('Не найдена группа подписки для дополнительного inbound')
    original = copy.deepcopy(state)
    backup = Path('/root/selfsteal-3xui/backups') / (
        'parallel-' + time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '-'
        + secrets.token_hex(4))
    backup.mkdir(parents=True, mode=0o700)
    files = parallel_backup_files(texts)
    groups = api.call('panel/api/hosts/list') or []
    secure_json(backup / 'state-before.json', original)
    secure_json(backup / 'inbounds-before.json', [r['before'] for r in records])
    secure_json(backup / 'hosts-before.json', groups)
    secure_json(backup / 'nginx-before.json', files)
    with db_read(state) as read_db, sqlite3.connect(backup / 'panel-before.db') as dest:
        read_db.backup(dest)
    os.chmod(backup / 'panel-before.db', 0o600)
    state['pending_parallel'] = {'backup': str(backup), 'stage': 'certificates'}
    save()
    try:
        parallel_ensure_certs(state, records, texts, root)
        parallel_write_file(PARALLEL_TLS, texts[PARALLEL_TLS].encode())
        # Validate the new TLS vhosts before moving the public port.
        parallel_nginx()
        state['pending_parallel']['stage'] = 'xray'
        save()
        for r in records:
            api.call('panel/api/inbounds/update/%s' % r['id'], payload(r['after']))
        api.restart()
        parallel_runtime(state, records)
        state['pending_parallel']['stage'] = 'nginx-stream'
        save()
        parallel_write_file(PARALLEL_STREAM, texts[PARALLEL_STREAM].encode())
        parallel_nginx()
        parallel_probe_443(records)
        state['pending_parallel']['stage'] = 'subscriptions'
        save()
        parallel_hosts_apply(api, records, groups)
        # No user identities, UUIDs, keys, shortIds, subscription IDs, or expiry
        # values are regenerated during the migration.
        for r in records:
            actual = next(x for x in api.list() if int(x['id']) == int(r['id']))
            if (parse(actual['settings']) != parse(r['before']['settings'])
                    or parse(actual['streamSettings']) != parse(r['after']['streamSettings'])):
                raise RuntimeError('Изменены параметры клиента или Reality на inbound ' + str(r['id']))
        state['reality_mode'] = 'parallel'
        state['reality_chain'] = False
        state['primary_internal_port'] = port
        state['parallel_sni_by_id'] = {str(r['id']): r['sni'] for r in records}
        for row in state.get('added_inbounds') or []:
            row['sni'] = state['parallel_sni_by_id'][str(row['id'])]
            row['address'] = row['sni']
        state['parallel_backup'] = str(backup)
        state.pop('pending_parallel', None)
        save()
        print('Независимые Reality включены через nginx TCP 443.')
        for r in records:
            print('Inbound ID %s: %s -> 127.0.0.1:%d' % (r['id'], r['sni'], r['port']))
        print('Ключи и пользователи сохранены. Обновите ссылки дополнительных Reality в приложениях.')
        print('Резервная копия: ' + str(backup))
    except Exception:
        try:
            parallel_restore_backup(state, api, backup, save)
        except Exception:
            state['pending_parallel'] = {'backup': str(backup),
                                         'rollback_incomplete': True}
            save()
            raise RuntimeError('Миграция не завершена и автоматический откат требует проверки. '
                               'Резервная копия: ' + str(backup)) from None
        raise RuntimeError('Миграция отменена; восстановлены прежние конфигурации nginx, Xray и hosts') from None



def parallel_existing_rows(state, api):
    if state.get('reality_mode') != 'parallel':
        raise RuntimeError('Сначала включите независимую маршрутизацию Reality')
    rows = {int(r['id']): r for r in api.list()}
    mapping = state.get('parallel_sni_by_id') or {}
    primary_id = int(state['inbound_id'])
    records = []
    for ref in [{'id': primary_id, 'port': int(state['primary_internal_port'])}] + list(state.get('added_inbounds') or []):
        rid = int(ref['id'])
        row = rows.get(rid)
        sni = parallel_validate_sni(mapping.get(str(rid), ''))
        port = int(ref['port'])
        if (not row or row.get('protocol') != 'vless'
                or int(row.get('port') or 0) != port
                or row.get('listen') != '127.0.0.1'
                or parse(row.get('streamSettings') or {}).get('realitySettings', {}).get('serverNames') != [sni]):
            raise RuntimeError('Независимый Reality изменён вне скрипта: inbound ' + str(rid))
        records.append({'id': rid, 'sni': sni, 'port': port, 'before': row, 'after': row})
    if len(records) != len(mapping) or len({r['sni'] for r in records}) != len(records):
        raise RuntimeError('Состояние SNI расходится с текущим списком inbound')
    expected_files, _ = parallel_texts(state, records)
    for path in expected_files:
        if not path.is_file() or path.is_symlink() or path.read_text() != expected_files[path]:
            raise RuntimeError('Конфигурация nginx была изменена извне: ' + str(path))
    return records


def parallel_add_inbound(state, port, sni, save):
    if state.get('removed') or any(state.get(k) for k in (
            'pending_parallel', 'pending_add_inbound', 'pending_chain', 'pending_hysteria')):
        raise RuntimeError('Установка удалена или осталась незавершённая операция')
    sni = parallel_validate_sni(sni)
    if not isinstance(port, int) or isinstance(port, bool) or not 1024 <= port <= 65535:
        raise RuntimeError('Внутренний порт должен быть в диапазоне 1024–65535')
    require_version(state)
    api = API(state)
    records = parallel_existing_rows(state, api)
    if sni in [x['sni'] for x in records]:
        raise RuntimeError('Этот SNI уже назначен другому Reality inbound')
    if any(int(x.get('port') or 0) == port and not inbound_uses_udp(x) for x in api.list()):
        raise RuntimeError('Выбранный TCP-порт занят inbound панели')
    if port in (443, int(state.get('target_port', 9443))):
        raise RuntimeError('Этот порт зарезервирован для nginx')
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.bind(('127.0.0.1', port))
    except OSError:
        raise RuntimeError('TCP-порт занят другим процессом') from None
    parallel_dns_check(sni, state['domain'])
    user = choose_existing_client(api)
    email = user['client']['email']
    uid = user['client']['uuid']
    old_bindings = set(user.get('inboundIds') or [])
    base = records[0]['before']
    stream = copy.deepcopy(parse(base['streamSettings']))
    reality = stream['realitySettings']
    private = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip('=')
    short_id = secrets.token_hex(8)
    reality.update(privateKey=private, shortIds=[short_id], serverNames=[sni],
                   target='127.0.0.1:%d' % int(state.get('target_port', 9443)), xver=1)
    reality.pop('dest', None)
    reality.setdefault('settings', {}).update(publicKey=public_key(private), fingerprint='firefox',
                                                serverName=sni, spiderX='/')
    stream.setdefault('tcpSettings', {})['acceptProxyProtocol'] = True
    tag = 'selfsteal-reality-' + str(port)
    if any(x.get('tag') == tag for x in api.list()):
        raise RuntimeError('Повторяется служебный тег inbound')
    inbound = dict(remark=tag, enable=True, expiryTime=0, total=0, up=0, down=0,
                   port=port, listen='127.0.0.1', protocol='vless', tag=tag,
                   trafficReset='never', trafficResetDay=1, disableFlow=False,
                   shareAddrStrategy='custom', shareAddr=sni,
                   sniffing=json.dumps({'enabled': True, 'destOverride': ['http', 'tls', 'quic'],
                                        'routeOnly': True}),
                   settings=json.dumps({'clients': [], 'decryption': 'none', 'fallbacks': []}),
                   streamSettings=json.dumps(stream))
    projected = records + [dict(sni=sni, port=port)]
    contents, root = parallel_texts(state, projected)
    files = parallel_backup_files(contents)
    backup = Path('/root/selfsteal-3xui/backups') / (
        'parallel-add-' + time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())
        + '-' + secrets.token_hex(4))
    backup.mkdir(mode=0o700, parents=True)
    secure_json(backup / 'nginx-before.json', files)
    secure_json(backup / 'state-before.json', state)
    secure_json(backup / 'user-before.json', user)
    state['pending_add_inbound'] = dict(port=port, tag=tag, sni=sni, backup=str(backup))
    save()
    created_id = None
    host_id = None
    try:
        parallel_ensure_certs(state, projected, contents, root)
        parallel_write_file(PARALLEL_TLS, contents[PARALLEL_TLS].encode())
        parallel_nginx()
        created = api.call('panel/api/inbounds/add', inbound)
        if not isinstance(created, dict) or created.get('id') is None:
            raise RuntimeError('Панель не вернула ID нового inbound')
        created_id = int(created['id'])
        state['pending_add_inbound']['id'] = created_id
        save()
        api.call('panel/api/clients/%s/attach' % urllib.parse.quote(email, safe=''),
                 {'inboundIds': [created_id]})
        check_client_binding(api, user, old_bindings | {created_id})
        api.restart()
        added = [x for x in api.list() if int(x['id']) == created_id]
        if len(added) != 1:
            raise RuntimeError('Панель потеряла созданный Reality inbound')
        projected[-1].update(id=created_id, before=added[0], after=added[0])
        parallel_runtime(state, projected)
        parallel_write_file(PARALLEL_STREAM, contents[PARALLEL_STREAM].encode())
        parallel_nginx()
        parallel_probe_443(projected)
        api.call('panel/api/hosts/add', parallel_host_payload(None, created_id, sni))
        groups = api.call('panel/api/hosts/list') or []
        matching = [g for g in groups if g.get('inboundIds') == [created_id]
                    and g.get('hosts') == [sni]]
        if len(matching) != 1 or not matching[0].get('groupId'):
            raise RuntimeError('Новая группа подписки не подтверждена')
        host_id = str(matching[0]['groupId'])
        state.setdefault('added_inbounds', []).append(
            dict(id=created_id, port=port, tag=tag, sni=sni, address=sni,
                 host_port=443, host_group_id=host_id, client_email=email,
                 client_uuid=uid))
        state['parallel_sni_by_id'][str(created_id)] = sni
        state.pop('pending_add_inbound', None)
        save()
        print('Независимый Reality создан: inbound %d, SNI %s, внешний TCP 443.' %
              (created_id, sni))
        print('Внутренний порт %d доступен только с localhost.' % port)
        print('Пользователь %s подключён. Обновите подписку клиента.' % terminal_label(email))
        print('Резервная копия: ' + str(backup))
    except Exception:
        failures = []
        try:
            parallel_restore_files(files)
            parallel_nginx()
        except Exception:
            failures.append('nginx')
        try:
            if created_id is not None:
                groups = api.call('panel/api/hosts/list') or []
                ids = [str(g['groupId']) for g in groups
                       if g.get('inboundIds') == [created_id] and g.get('groupId')]
                if ids:
                    api.call('panel/api/hosts/bulk/del', {'ids': ids})
                actual = canonical_client(api, email)
                if created_id in (actual.get('inboundIds') or []):
                    api.call('panel/api/clients/%s/detach' % urllib.parse.quote(email, safe=''),
                             {'inboundIds': [created_id]})
                api.call('panel/api/inbounds/del/%d' % created_id, {})
                api.restart()
                check_client_binding(api, user, old_bindings)
        except Exception:
            failures.append('3x-ui/Xray')
        if failures:
            state['pending_add_inbound']['rollback_incomplete'] = failures
            save()
            raise RuntimeError('Откат нового Reality требует проверки: ' + str(backup)) from None
        state.pop('pending_add_inbound', None)
        save()
        raise


def recover_parallel(state, save):
    pending = state.get('pending_parallel')
    if not pending:
        raise RuntimeError('Нет незавершённой миграции для восстановления')
    backup = Path(pending['backup'])
    if not backup.is_dir() or backup.parent != Path('/root/selfsteal-3xui/backups'):
        raise RuntimeError('Некорректный путь резервной копии')
    api = API(state)
    parallel_restore_backup(state, api, backup, save)
    print('Исходная Reality-цепочка восстановлена из ' + str(backup))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['inspect', 'authenticate', 'bootstrap', 'configure', 'add_inbound', 'add_hysteria', 'repair_chain', 'export', 'verify', 'rollback', 'route_preflight', 'publish', 'panel_access', 'migrate_parallel', 'recover_parallel'])
    parser.add_argument('--state', required=True)
    parser.add_argument('--port', type=int)
    parser.add_argument('--domain')
    parser.add_argument('--salamander', choices=['on', 'off'], default='on')
    parser.add_argument('--public', choices=['on', 'off'])
    parser.add_argument('--install-state')
    parser.add_argument('--sni-map')
    parser.add_argument('--sni')
    args = parser.parse_args()
    os.umask(0o077)
    state = json.loads(Path(args.state).read_text())
    state.setdefault('panel_binary', '/usr/local/x-ui/x-ui')
    state.setdefault('panel_db', '/etc/x-ui/x-ui.db')
    state.setdefault('target_port', 9443)
    save = lambda: secure_json(args.state, state)
    try:
        if args.command == 'panel_access':
            if args.public is None or not args.install_state:
                raise RuntimeError('Не указаны режим доступа или путь состояния установки')
            panel_access(state, args.public == 'on', args.install_state)
        elif args.command == 'migrate_parallel':
            if not args.sni_map:
                raise RuntimeError('Для миграции нужен файл сопоставления SNI')
            mapping = json.loads(Path(args.sni_map).read_text())
            if not isinstance(mapping, dict):
                raise RuntimeError('Ожидается JSON словарь ID → SNI')
            migrate_parallel(state, mapping, save)
        elif args.command == 'recover_parallel':
            recover_parallel(state, save)
        elif args.command == 'configure':
            configure(state, save)
        elif args.command == 'add_inbound':
            add_inbound(state, args.port, save, args.sni)
        elif args.command == 'add_hysteria':
            add_hysteria(state, args.port, args.domain or state.get('domain', ''), args.salamander == 'on', save)
        elif args.command == 'repair_chain':
            repair_chain(state, save)
        else:
            globals()[args.command](state)
        save()
    except Exception as exc:
        save()
        print('Помощник панели: ' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
PANEL_PY
}
write_placeholder() {
  python3 - "$DOMAIN" "$SITE_NAME" "$1" <<'PLACEHOLDER_PY'
import html
import os
import secrets
import sys

# Все 10 шаблонов встроены: установка через curl не требует дополнительных файлов.
TEMPLATES = {
    "01-centered.html": "<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>{{SITE_NAME}}</title><style>*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;background:#fff;color:#111827;font-family:Inter,system-ui,-apple-system,\"Segoe UI\",sans-serif}main{width:min(560px,100%);text-align:center}.status{display:inline-flex;gap:8px;align-items:center;padding:7px 12px;border:1px solid #e5e7eb;border-radius:999px;color:#4b5563;font-size:14px}.dot{width:8px;height:8px;border-radius:50%;background:#22c55e}h1{margin:24px 0 12px;font-size:52px;letter-spacing:-.04em}p{margin:0;color:#6b7280}code{display:block;margin-top:28px;padding:14px;border:1px solid #e5e7eb;border-radius:10px;background:#f9fafb;color:#374151;overflow-wrap:anywhere}footer{margin-top:28px;color:#9ca3af;font-size:13px}h1,.brand,.eyebrow,small,p,footer,.endpoint{overflow-wrap:anywhere}main,.left,.right,.box,.content{min-width:0;max-width:100%}</style></head><body><main><div class=\"status\"><span class=\"dot\"></span>API online</div><h1>{{SITE_NAME}}</h1><p>Сервисный API-шлюз {{SITE_NAME}}.</p><code>{{SITE_URL}}</code><footer>{{SITE_NAME}}</footer></main></body></html>",
    "02-card.html": "<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>{{SITE_NAME}}</title><style>*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;background:#f6f7f9;font-family:Inter,system-ui,sans-serif;color:#101828}.card{width:min(520px,100%);background:#fff;border:1px solid #eaecf0;border-radius:18px;padding:40px;box-shadow:0 12px 40px rgba(16,24,40,.06)}.badge{font-size:13px;color:#067647;background:#ecfdf3;display:inline-block;padding:6px 10px;border-radius:999px}h1{font-size:40px;margin:18px 0 8px;letter-spacing:-.03em}p{color:#667085;margin:0 0 26px}.endpoint{padding:13px 14px;border-radius:10px;background:#f9fafb;border:1px solid #eaecf0;font-family:monospace;color:#344054;overflow-wrap:anywhere}h1,.brand,.eyebrow,small,p,footer,.endpoint{overflow-wrap:anywhere}main,.left,.right,.box,.content{min-width:0;max-width:100%}</style></head><body><section class=\"card\"><div class=\"badge\">Operational</div><h1>{{SITE_NAME}}</h1><p>API endpoint is available and ready to accept requests.</p><div class=\"endpoint\">{{SITE_URL}}</div></section></body></html>",
    "03-left.html": "<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>{{SITE_NAME}}</title><style>*{box-sizing:border-box}body{margin:0;background:#fff;color:#0f172a;font-family:Inter,system-ui,sans-serif}.wrap{min-height:100vh;display:flex;align-items:center;padding:8vw}main{max-width:680px}.eyebrow{text-transform:uppercase;letter-spacing:.14em;font-size:12px;color:#64748b}h1{font-size:64px;line-height:.95;letter-spacing:-.055em;margin:18px 0 20px}p{font-size:18px;line-height:1.6;color:#64748b;max-width:560px}.line{margin-top:32px;padding-top:22px;border-top:1px solid #e2e8f0;font-family:monospace;color:#334155;overflow-wrap:anywhere}h1,.brand,.eyebrow,small,p,footer,.endpoint{overflow-wrap:anywhere}main,.left,.right,.box,.content{min-width:0;max-width:100%}</style></head><body><div class=\"wrap\"><main><div class=\"eyebrow\">{{SITE_NAME}}</div><h1>{{SITE_NAME}}</h1><p>Служебная точка доступа к API {{SITE_NAME}}.</p><div class=\"line\">{{SITE_URL}}</div></main></div></body></html>",
    "04-status-bar.html": "<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>{{SITE_NAME}}</title><style>*{box-sizing:border-box}body{margin:0;min-height:100vh;background:#fff;font-family:Inter,system-ui,sans-serif;color:#111827}header{height:58px;border-bottom:1px solid #eee;display:flex;align-items:center;justify-content:space-between;padding:0 28px;font-size:14px}.brand{font-weight:700}.ok{display:flex;align-items:center;gap:8px;color:#4b5563}.dot{width:8px;height:8px;border-radius:50%;background:#16a34a}main{min-height:calc(100vh - 58px);display:grid;place-items:center;padding:24px}.box{text-align:center;max-width:620px}h1{font-size:50px;margin:0 0 12px}p{color:#6b7280;margin:0}.endpoint{margin-top:28px;font-family:monospace;font-size:15px;color:#374151}h1,.brand,.eyebrow,small,p,footer,.endpoint{overflow-wrap:anywhere}main,.left,.right,.box,.content{min-width:0;max-width:100%}</style></head><body><header><div class=\"brand\">{{SITE_NAME}}</div><div class=\"ok\"><span class=\"dot\"></span>All systems operational</div></header><main><div class=\"box\"><h1>{{SITE_NAME}}</h1><p>Public service endpoint.</p><div class=\"endpoint\">{{SITE_URL}}</div></div></main></body></html>",
    "05-mono.html": "<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>{{SITE_NAME}}</title><style>*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#fafafa;color:#18181b;font-family:\"SFMono-Regular\",Consolas,monospace;padding:24px}main{width:min(700px,100%);border:1px solid #e4e4e7;background:#fff;padding:28px;border-radius:12px}.row{display:flex;justify-content:space-between;gap:20px;flex-wrap:wrap}h1{font-size:20px;margin:0}.status{color:#15803d}pre{margin:28px 0 0;white-space:pre-wrap;word-break:break-word;color:#52525b;line-height:1.7}h1,.brand,.eyebrow,small,p,footer,.endpoint{overflow-wrap:anywhere}main,.left,.right,.box,.content{min-width:0;max-width:100%}</style></head><body><main><div class=\"row\"><h1>{{SITE_NAME}}</h1><div class=\"status\">200 OK</div></div><pre>service: online\nurl: {{SITE_URL}}\nprotocol: https</pre></main></body></html>",
    "06-soft.html": "<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>{{SITE_NAME}}</title><style>*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:linear-gradient(180deg,#ffffff 0%,#f5f7fb 100%);font-family:Inter,system-ui,sans-serif;color:#111827;padding:24px}main{text-align:center;max-width:620px}.mark{width:52px;height:52px;margin:0 auto 20px;border-radius:14px;background:#111827;color:#fff;display:grid;place-items:center;font-weight:700}h1{font-size:46px;margin:0 0 10px;letter-spacing:-.04em}p{color:#6b7280;margin:0 0 26px}.endpoint{display:inline-block;padding:11px 15px;border:1px solid #e5e7eb;border-radius:999px;background:rgba(255,255,255,.8);font-family:monospace;color:#374151}h1,.brand,.eyebrow,small,p,footer,.endpoint{overflow-wrap:anywhere}main,.left,.right,.box,.content{min-width:0;max-width:100%}</style></head><body><main><div class=\"mark\">{{SITE_INITIAL}}</div><h1>{{SITE_NAME}}</h1><p>Secure API service endpoint.</p><div class=\"endpoint\">{{SITE_URL}}</div></main></body></html>",
    "07-outline.html": "<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>{{SITE_NAME}}</title><style>*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#fff;font-family:Arial,sans-serif;color:#111;padding:24px}main{width:min(600px,100%);padding:38px;border:2px solid #111;border-radius:4px}small{font-size:12px;text-transform:uppercase;letter-spacing:.15em}h1{font-size:48px;margin:18px 0 14px}p{margin:0;color:#555;line-height:1.6}.endpoint{margin-top:28px;padding:12px 0;border-top:1px solid #bbb;font-family:monospace;overflow-wrap:anywhere}h1,.brand,.eyebrow,small,p,footer,.endpoint{overflow-wrap:anywhere}main,.left,.right,.box,.content{min-width:0;max-width:100%}</style></head><body><main><small>{{SITE_NAME}}</small><h1>{{SITE_NAME}}</h1><p>This host provides access to the {{SITE_NAME}} infrastructure.</p><div class=\"endpoint\">{{SITE_URL}}</div></main></body></html>",
    "08-split.html": "<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>{{SITE_NAME}}</title><style>*{box-sizing:border-box}body{margin:0;min-height:100vh;background:#fff;font-family:Inter,system-ui,sans-serif;color:#111827}main{min-height:100vh;display:grid;grid-template-columns:1fr 1fr}.left,.right{padding:8vw;display:flex;flex-direction:column;justify-content:center}.left{border-right:1px solid #e5e7eb}h1{font-size:56px;line-height:1;margin:0 0 16px}p{color:#6b7280;line-height:1.6}.right{background:#fafafa}.label{font-size:13px;color:#6b7280;margin-bottom:10px}code{font-size:16px;overflow-wrap:anywhere}.status{margin-top:24px;color:#15803d}@media(max-width:700px){main{grid-template-columns:1fr}.left{border-right:0;border-bottom:1px solid #e5e7eb}}h1,.brand,.eyebrow,small,p,footer,.endpoint{overflow-wrap:anywhere}main,.left,.right,.box,.content{min-width:0;max-width:100%}</style></head><body><main><section class=\"left\"><h1>{{SITE_NAME}}</h1><p>Сервисный API-шлюз инфраструктуры {{SITE_NAME}}.</p></section><section class=\"right\"><div class=\"label\">Endpoint</div><code>{{SITE_URL}}</code><div class=\"status\">● Online</div></section></main></body></html>",
    "09-topline.html": "<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>{{SITE_NAME}}</title><style>*{box-sizing:border-box}body{margin:0;min-height:100vh;background:#fff;font-family:Inter,system-ui,sans-serif;color:#0f172a}.top{height:5px;background:#0f172a}main{min-height:calc(100vh - 5px);display:grid;place-items:center;padding:24px}.content{max-width:620px;text-align:center}h1{font-size:50px;margin:0 0 12px;letter-spacing:-.04em}p{color:#64748b;margin:0}.meta{margin-top:30px;display:flex;gap:12px;justify-content:center;flex-wrap:wrap}.meta span{padding:8px 11px;border:1px solid #e2e8f0;border-radius:8px;font-size:13px;color:#475569}.endpoint{font-family:monospace}h1,.brand,.eyebrow,small,p,footer,.endpoint{overflow-wrap:anywhere}main,.left,.right,.box,.content{min-width:0;max-width:100%}</style></head><body><div class=\"top\"></div><main><div class=\"content\"><h1>{{SITE_NAME}}</h1><p>Minimal service gateway.</p><div class=\"meta\"><span>Online</span><span class=\"endpoint\">{{SITE_URL}}</span></div></div></main></body></html>",
    "10-ultra-minimal.html": "<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>{{SITE_NAME}}</title><style>body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#fff;color:#111;font-family:system-ui,-apple-system,\"Segoe UI\",sans-serif;padding:24px}main{text-align:center}h1{font-size:42px;margin:0 0 10px}p{margin:0;color:#777}code{display:block;margin-top:24px;color:#444;word-break:break-all}h1,.brand,.eyebrow,small,p,footer,.endpoint{overflow-wrap:anywhere}main,.left,.right,.box,.content{min-width:0;max-width:100%}</style></head><body><main><h1>{{SITE_NAME}}</h1><p>Service is running.</p><code>{{SITE_URL}}</code></main></body></html>"
}

def render(template, domain, name):
    # Подстановка за один проход: введенное название не обрабатывается как шаблон.
    import re
    values = {
        'SITE_NAME': html.escape(name, quote=True),
        'SITE_URL': html.escape('https://' + domain, quote=True),
        'SITE_INITIAL': html.escape(name[0], quote=True),
    }
    return re.sub(r'\{\{(SITE_NAME|SITE_URL|SITE_INITIAL)\}\}',
                  lambda match: values[match[1]], template)

if __name__ == '__main__':
    domain, name, destination = sys.argv[1:]
    selected = secrets.choice(list(TEMPLATES))
    page = render(TEMPLATES[selected], domain, name)
    # Не перезаписываем существующие файлы или символические ссылки.
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        f.write(page)
    os.chmod(destination, 0o644)
    print(selected)
PLACEHOLDER_PY
}

state_get() { python3 - "$STATE" "$1" <<'PY'
import json,sys
v=json.load(open(sys.argv[1])).get(sys.argv[2], '')
print(str(v).lower() if isinstance(v,bool) else v)
PY
}
helper() { python3 "$PANEL_HELPER" "$1" --state "$STATE" "${@:2}"; }
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
    echo 'Настройка завершилась ошибкой; восстанавливаются управляемые конфигурации и прежние состояния сервисов.' >&2
    helper rollback 2>/dev/null || echo 'Откат панели требует проверки; сохраните закрытую резервную копию.' >&2
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
    echo "Закрытая резервная копия: $BACKUP. Установленные пакеты и выпущенные сертификаты сохраняются." >&2
  fi
  rm -rf -- "$WORK"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ "$ACTION" == panel-access ]]; then
  state_file=$(load_install_state || true)
  [[ -n "$state_file" && -r "$state_file" ]] || fail 'Нет сохранённой установки. Сначала выполните установку.'
  install -m 600 "$state_file" "$STATE"
  echo
  echo 'Доступ к панели из интернета'
  python3 - "$STATE" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
if s.get('removed'): sys.exit('Установка удалена; сначала выполните установку.')
print('Сохранённый режим: ' + ('включён' if s.get('publish_panel') else 'выключен'))
PY
  echo '1) Включить HTTPS-доступ по домену'
  echo '2) Выключить доступ из интернета'
  echo '0) Отмена'
  read -r -p 'Выберите действие [0–2]: ' PANEL_ACCESS_CHOICE
  case "$PANEL_ACCESS_CHOICE" in
    1) PANEL_PUBLIC=on ;;
    2) PANEL_PUBLIC=off ;;
    0) exit 0 ;;
    *) fail 'Введите 1, 2 или 0.' ;;
  esac
  emit_panel_helper > "$PANEL_HELPER"
  helper panel_access --public "$PANEL_PUBLIC" --install-state /root/selfsteal-3xui/state.json
  SUCCESS=1
  exit 0
fi

if [[ "$ACTION" == add-inbound || "$ACTION" == add-hysteria || "$ACTION" == repair-chain || "$ACTION" == parallel-reality || "$ACTION" == recover-parallel ]]; then
  echo
  echo '==============================================='
  echo '        3xUI Self-Steal — создание inbound'
  echo '==============================================='
  state_file=$(load_install_state || true)
  [[ -n "$state_file" && -r "$state_file" ]] || fail 'Нет сохранённой активной установки с данными панели. Сначала выполните установку.'
  HELPER_ARGS=()
  PANEL_ACTION=repair_chain
  ADD_PORT=0
  HYSTERIA_DOMAIN=''
  HYSTERIA_SALAMANDER=on
  PARALLEL_MAP=''
  if [[ "$ACTION" == parallel-reality || "$ACTION" == recover-parallel ]]; then
    PANEL_ACTION=migrate_parallel
    if [[ "$ACTION" == recover-parallel ]]; then
      PANEL_ACTION=recover_parallel
      echo 'Будет восстановлена конфигурация до незавершённой миграции.'
      read -r -p 'Для подтверждения введите RECOVER: ' PARALLEL_CONFIRM
      [[ "$PARALLEL_CONFIRM" == RECOVER ]] || exit 0
    else
      echo 'Независимые Reality на TCP 443: каждый дополнительный inbound получит отдельный SNI.'
      echo 'Основной домен сохраняется. Клиентам дополнительных inbound потребуется обновить ссылку.'
      read -r -p 'Подготовить безопасную миграцию? [y/N]: ' PARALLEL_OK
      [[ "${PARALLEL_OK,,}" == y ]] || exit 0
      PARALLEL_MAP=$(mktemp /tmp/selfsteal-sni.XXXXXXXX)
      chmod 600 "$PARALLEL_MAP"
      python3 - "$state_file" "$PARALLEL_MAP" <<'PY'
import json,sys
state=json.load(open(sys.argv[1]))
m={}
for row in state.get('added_inbounds') or []:
    ident=str(row['id'])
    if ident in m: sys.exit('Повторяется ID inbound')
    print('Inbound ID %s, прежний внутренний TCP-порт %d:' % (ident,row['port']))
    m[ident]=input('  Уникальный домен/SNI (DNS на тот же сервер): ').strip()
with open(sys.argv[2],'w') as f: json.dump(m,f)
PY
      read -r -p 'Для изменения работающего nginx и Xray введите PARALLEL REALITY: ' PARALLEL_CONFIRM
      [[ "$PARALLEL_CONFIRM" == 'PARALLEL REALITY' ]] || { rm -f "$PARALLEL_MAP"; exit 0; }
      HELPER_ARGS=(--sni-map "$PARALLEL_MAP")
    fi
  fi
  if [[ "$ACTION" == add-hysteria ]]; then
    PANEL_ACTION=add_hysteria
    read -r -p 'Домен Hysteria 2 (Enter — домен Self-Steal): ' HYSTERIA_DOMAIN
    if [[ -z "$HYSTERIA_DOMAIN" ]]; then
      HYSTERIA_DOMAIN=$(python3 - "$state_file" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get('domain',''))
PY
)
    fi
    HYSTERIA_DOMAIN=${HYSTERIA_DOMAIN,,}
    read -r -p 'UDP-порт Hysteria 2 [443]: ' ADD_PORT
    ADD_PORT=${ADD_PORT:-443}
    read -r -p 'Включить Salamander? [Y/n]: ' MASK_CHOICE
    case "${MASK_CHOICE,,}" in
      ''|y|yes|д|да) HYSTERIA_SALAMANDER=on ;;
      n|no|н|нет) HYSTERIA_SALAMANDER=off ;;
      *) fail 'Ответьте Y или n.' ;;
    esac
  fi
  if [[ "$ACTION" == add-inbound ]]; then
    PANEL_ACTION=add_inbound
    read -r -p 'Локальный TCP-порт нового inbound: ' ADD_PORT
    if [[ $(python3 - "$state_file" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get('reality_mode','chain'))
PY
) == parallel ]]; then
      read -r -p 'Новый уникальный домен/SNI, DNS на этот сервер: ' PARALLEL_ADD_SNI
      HELPER_ARGS=(--sni "$PARALLEL_ADD_SNI")
    fi
    [[ "$ADD_PORT" =~ ^[0-9]{1,5}$ ]] || fail 'Введите целый номер TCP-порта от 1 до 65535.'
  fi
  ADD_PORT=$(python3 - "$state_file" "$STATE" "$ADD_PORT" "$ACTION" <<'PY'
import json,os,re,sys
source,destination,raw,action=sys.argv[1:]
if action not in ('add-inbound','add-hysteria'):
    raw='0'
if not re.fullmatch(r'[0-9]{1,5}',raw): sys.exit('Некорректный номер порта.')
port=int(raw)
if action in ('add-inbound','add-hysteria') and not 1 <= port <= 65535: sys.exit('Порт должен быть от 1 до 65535.')
with open(source) as f: state=json.load(f)
if state.get('removed'): sys.exit('Сохранённая установка помечена как удалённая; сначала выполните установку снова.')
required=('domain','panel_url','panel_username','panel_password','inbound_id')
if any(not state.get(key) for key in required): sys.exit('В состоянии установки отсутствуют домен, inbound или данные входа в панель.')
with open(destination,'w') as f: json.dump(state,f)
os.chmod(destination,0o600)
print(port)
PY
) || fail 'Не удалось проверить сохранённое состояние или номер порта.'
  emit_panel_helper > "$PANEL_HELPER"
  if [[ "$ACTION" == add-inbound ]]; then HELPER_ARGS+=(--port "$ADD_PORT"); fi
  if [[ "$ACTION" == add-hysteria ]]; then HELPER_ARGS=(--port "$ADD_PORT" --domain "$HYSTERIA_DOMAIN" --salamander "$HYSTERIA_SALAMANDER"); fi
  if helper "$PANEL_ACTION" "${HELPER_ARGS[@]}"; then
    [[ -z "$PARALLEL_MAP" ]] || rm -f "$PARALLEL_MAP"
    persist_tmp="/root/selfsteal-3xui/state.json.tmp.$$"
    install -m 600 "$STATE" "$persist_tmp"
    mv -f -- "$persist_tmp" /root/selfsteal-3xui/state.json
    SUCCESS=1
    exit 0
  else
    rc=$?
    [[ -z "$PARALLEL_MAP" ]] || rm -f "$PARALLEL_MAP"
    if python3 - "$STATE" <<'PY'
import json,sys
try: state=json.load(open(sys.argv[1]))
except Exception: sys.exit(1)
sys.exit(0 if state.get('pending_parallel') or state.get('pending_add_inbound',{}).get('rollback_incomplete') or state.get('pending_chain') or state.get('pending_hysteria',{}).get('rollback_incomplete') else 1)
PY
    then
      persist_tmp="/root/selfsteal-3xui/state.json.tmp.$$"
      install -m 600 "$STATE" "$persist_tmp"
      mv -f -- "$persist_tmp" /root/selfsteal-3xui/state.json
      echo 'Откат не завершён: исходные настройки и подробности сохранены; проверьте цепочку, inbound и panel/hosts в панели.' >&2
    fi
    exit "$rc"
  fi
fi

if [[ -z $DOMAIN ]]; then read -r -p 'Домен (полное имя, без http:// или https://): ' DOMAIN; fi
DOMAIN=${DOMAIN,,}
CERT_WAS_PRESENT=0
if command -v certbot >/dev/null && certbot certificates 2>/dev/null | grep -Fq "Certificate Name: $DOMAIN"; then
  CERT_WAS_PRESENT=1
fi
python3 - "$DOMAIN" <<'PY'
import re,sys
s=sys.argv[1]
if len(s)>253 or '.' not in s or not all(re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', x) for x in s.split('.')):
    sys.exit('Некорректное имя домена. Используйте форму ASCII/punycode.')
PY
SITE_NAME=''
if (( ! CHECK )); then
  read -r -p 'Название сайта для страницы-заглушки: ' SITE_NAME
  SITE_NAME=$(python3 - "$SITE_NAME" <<'PY'
import sys
name = sys.argv[1].strip()
if not name or len(name) > 120 or any(ord(c) < 32 or ord(c) == 127 for c in name):
    sys.exit('Введите название длиной от 1 до 120 символов без управляющих символов.')
print(name)
PY
)
fi
EMAIL=''
if (( ! CHECK )); then read -r -p 'Email для Let’s Encrypt (необязательно): ' EMAIL; fi
[[ -z $EMAIL || $EMAIL =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || fail 'Некорректный email.'
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
if (( ! CHECK )); then read -r -p "TCP-порты SSH [${DETECTED_SSH:-22}] (через пробел): " SSH_PORTS; fi
SSH_PORTS=${SSH_PORTS:-${DETECTED_SSH:-22}}
PANEL_URL=''; PANEL_USER=''; PANEL_PASS=''; PANEL_2FA=''
if (( ! CHECK )) && [[ -e /etc/x-ui/x-ui.db ]]; then
  read -r -p 'Локальный URL/basePath существующей панели (Enter для автоопределения): ' PANEL_URL
  read -r -p 'Логин существующего администратора: ' PANEL_USER
  read -r -s -p 'Пароль существующего администратора: ' PANEL_PASS; echo
  read -r -s -p 'Код двухфакторной аутентификации администратора (необязательно): ' PANEL_2FA; echo
fi
PUBLIC_PANEL=n
if (( ! CHECK )); then
  read -r -p "Опубликовать панель с входом по паролю через HTTPS на $DOMAIN по секретному basePath? [Y/n, Enter — да]: " PUBLIC_PANEL
  PUBLIC_PANEL=${PUBLIC_PANEL:-y}
  [[ ${PUBLIC_PANEL,,} == y || ${PUBLIC_PANEL,,} == n ]] || fail 'Введите y (да) или n (нет).'
  if [[ ${PUBLIC_PANEL,,} == y && $PANEL_USER == admin && $PANEL_PASS == admin ]]; then
    fail 'Перед публикацией существующей панели смените стандартные учетные данные администратора через закрытое соединение.'
  fi
fi
SECURITY=n
if (( ! CHECK )); then
  read -r -p 'Настроить UFW (запрет входящих, разрешение исходящих) и включить fail2ban для SSH? [Y/n, Enter — да]: ' SECURITY
  SECURITY=${SECURITY:-y}
  [[ ${SECURITY,,} == y || ${SECURITY,,} == n ]] || fail 'Введите y (да) или n (нет).'
  if [[ ${SECURITY,,} == n ]]; then echo 'ВНИМАНИЕ: настройка межсетевого экрана и fail2ban пропущена. Ограничение внешних портов не проверяется и не применяется.' >&2; fi
fi
export DOMAIN SITE_NAME EMAIL SSH_PORTS PANEL_URL PANEL_USER PANEL_PASS PANEL_2FA SECURITY PUBLIC_PANEL SERVICES_BEFORE_JSON CERT_WAS_PRESENT UFW_WAS_ACTIVE
python3 - "$STATE" <<'PY'
import json,os,sys
ports=[int(p) for p in os.environ['SSH_PORTS'].split()]
if not ports or any(p<1 or p>65535 for p in ports): sys.exit('Некорректные порты SSH')
s=dict(domain=os.environ['DOMAIN'],email=os.environ['EMAIL'],ssh_ports=sorted(set(ports)),panel_binary='/usr/local/x-ui/x-ui',panel_db='/etc/x-ui/x-ui.db',panel_url=os.environ['PANEL_URL'],panel_username=os.environ['PANEL_USER'],panel_password=os.environ['PANEL_PASS'],target_port=9443,allow_firewall=os.environ['SECURITY'].lower()=='y')
s['site_name']=os.environ['SITE_NAME']
s['publish_panel']=os.environ['PUBLIC_PANEL'].lower()=='y'
s['panel_snippet']='/etc/nginx/snippets/selfsteal-3xui-panel-'+s['domain']+'.conf'
s['panel_map']='/etc/nginx/conf.d/selfsteal-3xui-panel-'+s['domain']+'-map.conf'
s['panel_two_factor_code']=os.environ['PANEL_2FA']
s['services_before']=json.loads(os.environ['SERVICES_BEFORE_JSON'])
s['ufw_was_active']=os.environ['UFW_WAS_ACTIVE'] == '1'
s['cert_was_present']=os.environ['CERT_WAS_PRESENT'] == '1'
s['packages_added_by_script']=[]
s['removed']=False
from pathlib import Path
previous=Path('/root/selfsteal-3xui/state.json')
if previous.is_file():
    old=json.loads(previous.read_text())
    if old.get('domain')==s['domain'] and not old.get('removed'):
        if old.get('pending_chain') or old.get('pending_add_inbound'):
            sys.exit('Есть незавершённая операция с inbound; сначала проверьте сохранённое состояние.')
        for key in ('added_inbounds','reality_chain'):
            if key in old: s[key]=old[key]
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
except socket.gaierror as e: sys.exit(f'Ошибка DNS-запроса: {e}')
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
print('Обнаруженные публичные адреса:', ', '.join(sorted(local)) or '(недоступны)')
if not dns or not dns.issubset(local):
 print('Несовпадение: исправьте все записи A/AAAA, включая устаревшие IPv6. При работе за NAT для продолжения нужно проверить проброс TCP-портов 80/443.',file=sys.stderr)
 sys.exit(42)
PY
if (( DNS_RC )); then
  (( DNS_RC == 42 )) || fail 'Предварительная проверка DNS и публичного адреса не пройдена.'
  (( ! CHECK )) || fail 'Несовпадение DNS: режим проверки не вносит изменений и не позволяет подтвердить работу за NAT.'
  read -r -p 'Продолжение за NAT: введите I VERIFIED DNS AND PORT FORWARDING после проверки DNS и проброса портов: ' ANSWER
  [[ $ANSWER == 'I VERIFIED DNS AND PORT FORWARDING' ]] || fail 'Продолжение при несовпадении DNS не подтверждено.'
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
  nginx -T > "$WORK/nginx.txt" 2>&1 || fail 'Существующая конфигурация nginx некорректна.'
  EXISTING_SITE=$(python3 - "$WORK/nginx.txt" "$DOMAIN" "$STOCK_DEFAULT" <<'PY'
import re,sys
text=open(sys.argv[1]).read(); domain=sys.argv[2]; matches=[]; checked=[]
for path,body in re.findall(r'# configuration file ([^:\n]+):\n(.*?)(?=\n# configuration file |\Z)',text,re.S):
 if sys.argv[3]=='1' and path in ('/etc/nginx/sites-enabled/default','/etc/nginx/sites-available/default'): continue
 checked.append(body)
 if any(domain in names.split() for names in re.findall(r'\bserver_name\s+([^;]+);',body)):
  if not re.search(r'listen\s+127\.0\.0\.1:9443\s+ssl[^;]*proxy_protocol',body) or not re.search(r'ssl_protocols\s+TLSv1\.3\s*;',body) or 'ssl_reject_handshake on;' not in body or '/.well-known/acme-challenge/' not in body:
   sys.exit(f'Конфликт пользовательского сайта nginx: {path}. Настройте адрес self-steal с TLS 1.3/PROXY protocol и ACME вручную; файлы не заменены.')
  if f'/etc/letsencrypt/live/{domain}/fullchain.pem' not in body:
   sys.exit(f'Конфликт существующей конфигурации сертификата: {path}')
  matches.append(path)
if len(set(matches))>1: sys.exit('Домен настроен в нескольких файлах nginx; сначала устраните конфликт.')
if matches: print(matches[0])
elif any(re.search(r'listen\s+(?:\[::\]:)?80[^;]*default_server',body) and not re.search(r'return\s+444\s*;',body) for body in checked):
 sys.exit('Существующий HTTP-сайт по умолчанию не отклоняет неизвестные домены. Сохраните его или настройте return 444 вручную перед повторным запуском.')
PY
) || fail 'Конфликт сайта nginx. Существующие файлы не изменены.'
fi
python3 - "$STATE" "$EXISTING_SITE" <<'PY'
import json,sys
p=sys.argv[1]; s=json.load(open(p)); s['nginx_site']=sys.argv[2]; json.dump(s,open(p,'w'))
PY
helper route_preflight
python3 - "$EXISTING_SITE" <<'PY'
import subprocess,sys
for line in subprocess.check_output(['ss','-ltnpH'],text=True).splitlines():
 address=line.split()[3]; port=int(address.rsplit(':',1)[1])
 if port==80 and 'nginx' not in line: sys.exit('TCP 80 занят сервисом, отличным от nginx.')
 if port==9443 and not (sys.argv[1] and 'nginx' in line and address.startswith('127.0.0.1:')):
  sys.exit('Целевой TCP-порт 9443 занят несовместимым сервисом.')
PY
if [[ $(state_get allow_firewall) == true ]]; then
  # Do not fight another firewall manager or silently retain public panel rules.
  systemctl is-active --quiet firewalld && fail 'Активен firewalld; используйте существующее управление межсетевым экраном вместо UFW.' || true
  if command -v ufw >/dev/null; then
    python3 - <<'PY'
import pathlib,re,sys
p=pathlib.Path('/etc/default/ufw')
if not p.is_file(): sys.exit('Отсутствует файл политики IPv6 UFW; проверьте установку перед настройкой межсетевого экрана.')
s=p.read_text(); values=re.findall(r'^\s*IPV6\s*=\s*["\']?(yes|no)["\']?\s*(?:#.*)?$',s,re.M)
if len(values)!=1: sys.exit('Параметр IPV6 UFW неоднозначен; оставьте ровно одну настройку IPV6=yes/no.')
if values[0]=='no':
 rules=pathlib.Path('/etc/ufw/user6.rules')
 if rules.exists() and re.search(r'^-A ufw6-user-(?:input|forward)\b',rules.read_text(),re.M):
  sys.exit('IPv6 в UFW отключен, но сохранены пользовательские правила IPv6 input/forward. Проверьте или удалите их перед повторным запуском: включение IPv6 может открыть лишние порты.')
 print('Будет включена фильтрация IPv6 в UFW; неактивных пользовательских входящих правил IPv6 не найдено.')
PY
    ufw status numbered > "$WORK/ufw.txt"
    python3 - "$WORK/ufw.txt" "$SSH_PORTS" <<'PY'
import re,sys
allowed={80,443,*map(int,sys.argv[2].split())}
for line in open(sys.argv[1]):
 if 'ALLOW' not in line and 'LIMIT' not in line: continue
 match=re.search(r'\]\s+(\d+)/tcp(?:\s|$)',line)
 if not match or int(match[1]) not in allowed:
  sys.exit('Существующее правило UFW allow/limit выходит за пределы SSH/80/443. Проверьте его вручную; скрипт не сбрасывает правила межсетевого экрана.')
PY
  fi
fi
if (( CHECK )); then echo 'Проверка без изменений пройдена. Пакеты, версии программ, сервисы и рабочие файлы не изменены.'; exit 0; fi
printf '\nПлан: %s; self-steal 443 -> 127.0.0.1:9443; порты SSH: %s.\n' "$DOMAIN" "$SSH_PORTS"
if [[ -z $EXISTING_SITE ]]; then
  printf 'Страница-заглушка: название «%s», адрес https://%s; случайный вариант из 10.\n' "$SITE_NAME" "$DOMAIN"
fi
echo 'Сохранить существующие идентификаторы, администратора и локальный адрес панели. Установить зависимости, получить сертификат, настроить nginx и 3x-ui.'
if [[ $(state_get publish_panel) == true ]]; then
  echo "Опубликовать панель с входом по паролю только по секретному HTTPS basePath на $DOMAIN; без публичного порта 2053 и панели в корне домена."
else
  echo 'Не добавлять публичный маршрут панели; удалить только неизмененные фрагменты и include панели, созданные скриптом. Пользовательские маршруты сохраняются.'
fi
echo 'При ошибке управляемые файлы и состояния сервисов восстанавливаются; пакеты и сертификаты сохраняются.'
if (( STOCK_DEFAULT )); then echo 'Неизмененный стандартный сайт nginx будет отключен с резервным копированием; пользовательские сайты сохраняются.'; fi
read -r -p 'Для подтверждения всех изменений введите APPLY: ' ANSWER
[[ $ANSWER == APPLY ]] || fail 'Отменено без изменений.'
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
if [[ -n $EXISTING_SITE ]]; then
  ACTUAL_SITE=$(readlink -f "$EXISTING_SITE")
  [[ $ACTUAL_SITE == "$SITE" ]] || snapshot "$ACTUAL_SITE"
fi
snapshot "$(state_get panel_snippet)"
snapshot "$(state_get panel_map)"
snapshot "$RESULT/access.json"
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
apt-get install -y "${INSTALL_PACKAGES[@]}"
export INSTALL_PACKAGES="${INSTALL_PACKAGES[*]}" PREINSTALLED_PACKAGES="${PREINSTALLED_PACKAGES[*]}"
python3 - "$STATE" <<'PY'
import json,os,sys
s=json.load(open(sys.argv[1]))
pre=set(os.environ.get('PREINSTALLED_PACKAGES','').split())
s['packages_added_by_script']=[p for p in os.environ.get('INSTALL_PACKAGES','').split() if p and p not in pre]
with open(sys.argv[1],'w') as f: json.dump(s,f)
PY
if (( STOCK_DEFAULT || ! NGINX_WAS_INSTALLED )) && [[ -L /etc/nginx/sites-enabled/default && $(readlink -f /etc/nginx/sites-enabled/default) == /etc/nginx/sites-available/default ]]; then
  snapshot /etc/nginx/sites-enabled/default
  rm /etc/nginx/sites-enabled/default
fi
if [[ $(state_get is_existing) != true ]]; then
  case $(uname -m) in x86_64) ARCH=amd64;; aarch64|arm64) ARCH=arm64;; *) fail 'Для новой установки поддерживаются только amd64/arm64.';; esac
  echo "Получение данных закрепленной версии 3x-ui $XUI_VERSION с GitHub..."
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    "https://api.github.com/repos/MHSanaei/3x-ui/releases/tags/v$XUI_VERSION" -o "$WORK/release.json"
  python3 - "$WORK/release.json" "$ARCH" "$WORK/release-meta" <<'PY'
import json,re,sys
r=json.load(open(sys.argv[1])); name=f'x-ui-linux-{sys.argv[2]}.tar.gz'
if r.get('tag_name')!='v3.8.5' or r.get('draft') or r.get('prerelease'): sys.exit('Некорректный закрепленный выпуск')
a=next((a for a in r['assets'] if a['name']==name),None)
if not a or not re.fullmatch(r'sha256:[0-9a-f]{64}',a.get('digest','')): sys.exit('Официальный API не вернул SHA256; выполнение отменено')
url=a['browser_download_url']
if url!=f'https://github.com/MHSanaei/3x-ui/releases/download/v3.8.5/{name}': sys.exit('Неожиданный источник файла выпуска')
open(sys.argv[3],'w').write(url+'\n'+a['digest'][7:]+'\n')
PY
  mapfile -t META < "$WORK/release-meta"
  printf 'Загрузка проверенного архива 3x-ui: <%s>\n' "${META[0]}"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "${META[0]}" -o "$WORK/release.tar.gz"
  printf '%s  %s\n' "${META[1]}" "$WORK/release.tar.gz" | sha256sum --check --status || fail 'Контрольная сумма SHA256 выпуска не совпадает.'
  # Validate all paths before extraction, including symlinks/hardlinks.
  python3 - "$WORK/release.tar.gz" <<'PY'
import pathlib,sys,tarfile
with tarfile.open(sys.argv[1]) as t:
 for m in t.getmembers():
  p=pathlib.PurePosixPath(m.name)
  if p.is_absolute() or '..' in p.parts or not p.parts or p.parts[0]!='x-ui' or m.issym() or m.islnk() or not (m.isfile() or m.isdir()): sys.exit('Небезопасный элемент архива выпуска')
PY
  [[ ! -e /usr/local/x-ui ]] || fail 'Каталог /usr/local/x-ui существует без поддерживаемой базы данных; перезапись отменена.'
  [[ ! -e /etc/x-ui ]] || fail 'При новой установке обнаружен существующий каталог /etc/x-ui; проверьте его вручную перед продолжением.'
  FRESH_FILES=1
  tar -xzf "$WORK/release.tar.gz" -C /usr/local
  chmod 700 /usr/local/x-ui
  chmod 755 /usr/local/x-ui/x-ui /usr/local/x-ui/x-ui.sh /usr/local/x-ui/bin/xray-linux-"$ARCH"
  install -m 755 /usr/local/x-ui/x-ui.sh /usr/bin/x-ui
  SERVICE_SOURCE=/usr/local/x-ui/x-ui.service
  [[ -f $SERVICE_SOURCE ]] || SERVICE_SOURCE=/usr/local/x-ui/x-ui.service.debian
  [[ -f $SERVICE_SOURCE ]] || fail 'В проверенном архиве нет поддерживаемого сервиса Debian.'
  install -m 644 "$SERVICE_SOURCE" /etc/systemd/system/x-ui.service
  mkdir -p /etc/systemd/system/x-ui.service.d
  printf '[Service]\nUMask=0077\n' > /etc/systemd/system/x-ui.service.d/selfsteal-permissions.conf
  systemctl daemon-reload
  helper bootstrap
  systemctl enable --now x-ui
fi
# Preserve compatible site assets/custom routes; only the owned panel include changes.
if [[ -n $EXISTING_SITE ]]; then
  ROOT=$(python3 - "$EXISTING_SITE" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
m=re.search(r'location\s+(?:\^~\s+)?/\.well-known/acme-challenge/\s*\{[^}]*\broot\s+([^;]+);',s,re.S)
if not m: sys.exit('Не удалось безопасно определить существующий корневой каталог ACME')
print(m[1].strip())
PY
)
else
  mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
  cat > "$SITE" <<NGINX_HTTP
# Managed by selfsteal-3xui; panel routing uses a separately owned snippet.
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
  [[ ! -e $ROOT ]] || fail "Конфликт с существующим корневым каталогом сайта $ROOT; файлы сайта не будут перезаписаны."
  FRESH_ROOT=1
  mkdir -p "$ROOT/.well-known/acme-challenge"
  chmod 755 "$ROOT" "$ROOT/.well-known" "$ROOT/.well-known/acme-challenge"
  PLACEHOLDER_TEMPLATE=$(write_placeholder "$ROOT/index.html")
  chmod 644 "$ROOT/index.html"
  python3 - "$STATE" <<'PY'
import json,sys
p=sys.argv[1]; s=json.load(open(p)); s['fresh_root']=True
with open(p,'w') as f: json.dump(s,f)
PY
else
  [[ -d $ROOT/.well-known/acme-challenge ]] || fail 'Существующий корневой каталог ACME отсутствует; создайте его вручную без изменения прав сайта и его файлов.'
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
if n!=1: sys.exit('Нельзя безопасно включить IPv6 в UFW: параметр IPV6 отсутствует или неоднозначен.')
if updated!=s: p.write_text(updated)
PY
  ufw default deny incoming
  ufw default allow outgoing
  for port in $SSH_PORTS; do ufw allow "$port/tcp"; done
  ufw allow 80/tcp; ufw allow 443/tcp
  ufw --force enable
fi
echo "Получение сертификата Let's Encrypt через HTTP-01 для $DOMAIN..."
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
python3 - "$STATE" "${EXISTING_SITE:-$SITE}" <<'PY'
import json,sys
p=sys.argv[1]; s=json.load(open(p)); s['nginx_site']=sys.argv[2]; json.dump(s,open(p,'w'))
PY
helper publish
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
echo 'Настройка и проверка входящего подключения Reality в 3x-ui...'
helper configure
helper verify
helper export
# The real exported client configuration is used, not a synthesized mock.
XRAY=''
for binary in /usr/local/x-ui/bin/xray-linux-*; do
  if [[ -f $binary && -x $binary ]]; then XRAY=$binary; break; fi
done
[[ -n $XRAY && -x $XRAY ]] || fail 'Не найден встроенный исполняемый файл Xray.'
[[ -s $RESULT/client.json && -s $RESULT/client.txt ]] || fail 'Помощник не экспортировал реальные файлы клиента.'
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
echo 'Проверка экспортированного клиента VLESS через прокси Reality...'
for attempt in {1..30}; do
  if curl --fail --silent --show-error --max-time 10 --socks5-hostname "127.0.0.1:$SMOKE_PORT" https://api.ipify.org > "$RESULT/proxy-exit-ip.txt" 2>"$WORK/proxy-curl.err"; then break; fi
  if (( attempt == 30 )); then echo 'Последняя диагностика curl:' >&2; cat "$WORK/proxy-curl.err" >&2; fi
  kill -0 "$SMOKE_PID" 2>/dev/null || fail 'Клиент Xray остановился; проверьте закрытый журнал тестового подключения.'
  sleep 1
done
[[ -s $RESULT/proxy-exit-ip.txt ]] || fail 'Проверка HTTPS через клиент Reality не пройдена; изучите диагностику curl выше и закрытый журнал Xray.'
echo 'Проверка HTTPS через прокси Reality...'
curl --fail --silent --show-error --max-time 30 --socks5-hostname "127.0.0.1:$SMOKE_PORT" https://example.com/ -o "$WORK/proxy-https.html"
kill "$SMOKE_PID"; wait "$SMOKE_PID" || true; SMOKE_PID=''
echo "Проверка публичного HTTPS-сайта маскировки для $DOMAIN..."
curl --fail --silent --show-error --max-time 30 "https://$DOMAIN/" -o "$WORK/ordinary-https.html"
if [[ $(state_get public_url) == https://* ]]; then
  echo 'Проверка публичного маршрута HTTPS API панели...'
  curl --fail --silent --show-error --max-time 30 "$(state_get public_url)csrf-token" -o "$WORK/public-panel-csrf.json"
  python3 - "$WORK/public-panel-csrf.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if r.get('success') is not True or not isinstance(r.get('obj'),str) or not r['obj']:
    sys.exit('Публичный маршрут панели не вернул корректный CSRF-токен сессии')
PY
fi
# Independent trusted TLS and strict wrong/no-SNI proof through the public endpoint.
python3 - "$DOMAIN" <<'PY'
import socket,ssl,sys
host=sys.argv[1]
ctx=ssl.create_default_context(); ctx.minimum_version=ssl.TLSVersion.TLSv1_3
with socket.create_connection((host,443),timeout=15) as s:
 with ctx.wrap_socket(s,server_hostname=host) as t:
  if t.version()!='TLSv1.3': sys.exit('Обычное HTTPS-соединение не согласовало TLS 1.3')
  print('Доверенный TLS 1.3 и сертификат домена: проверены')
for name in ('invalid.example',None):
 c=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT); c.check_hostname=False; c.verify_mode=ssl.CERT_NONE
 try:
  with socket.create_connection((host,443),timeout=15) as s:
   with c.wrap_socket(s,server_hostname=name): pass
 except ssl.SSLError: continue
 except OSError as e: sys.exit(f'Не удалось однозначно проверить неверный или отсутствующий SNI: {e}')
 sys.exit(f'Неожиданно принято TLS-соединение с SNI {name!r}')
print('Неверный или отсутствующий SNI: соединение отклонено')
PY
helper verify
echo 'Проверка продления сертификата в тестовом режиме...'
certbot renew --dry-run --run-deploy-hooks --cert-name "$DOMAIN"
qrencode -t UTF8 -o "$RESULT/client-qr.txt" < "$RESULT/client.txt"
cp "$STATE" "$BACKUP/final-state.json"; chmod 600 "$BACKUP/final-state.json"
mkdir -p /root/selfsteal-3xui
cp "$STATE" /root/selfsteal-3xui/state.json
chmod 600 /root/selfsteal-3xui/state.json
chmod 600 "$RESULT"/*
printf '\n============================================================\n'
printf '  УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА\n'
printf '============================================================\n'

echo
echo '--- Панель 3x-ui ---'
python3 - "$RESULT/access.json" <<'PY'
import json,sys
a=json.load(open(sys.argv[1]))
print('  Локальный URL:    ' + a['browser_url'])
print('  Логин:            ' + a['username'])
print('  Пароль:           ' + a['password'])
print('  SSH-туннель:      ' + a['ssh_tunnel'])
if a.get('public_url'):
    print('  Публичный URL:    ' + a['public_url'])
statuses = {
    'disabled': 'публикация отключена',
    'disabled-managed-route-removed': 'публикация отключена; маршрут скрипта удален',
    'disabled-custom-routes-preserved': 'публикация скриптом отключена; пользовательские маршруты сохранены',
    'existing-custom-route-preserved': 'существующий пользовательский маршрут сохранен',
    'enabled-managed-route': 'публикация включена; маршрут создан скриптом',
}
print('  Публикация:       ' + statuses.get(a['public_panel_status'], a['public_panel_status']))
print('  Данные доступа:   ' + sys.argv[1] + ' (только root)')
PY
echo '  Сохраните пароль и секретный URL панели в безопасном месте.'

echo
echo '--- VLESS + Reality ---'
printf '  Выходной IP прокси: %s\n' "$(cat "$RESULT/proxy-exit-ip.txt")"
echo '  Секретная ссылка клиента:'
cat "$RESULT/client.txt"

echo
echo '--- QR-код клиента ---'
cat "$RESULT/client-qr.txt"

echo
echo '--- Файлы и сайт ---'
printf '  Результаты:       %s\n' "$RESULT"
printf '  Резервная копия:  %s\n' "$BACKUP"
if (( FRESH_ROOT )); then
  printf '  Страница сайта:   %s/index.html\n' "$ROOT"
  printf '  Шаблон:           %s\n' "$PLACEHOLDER_TEMPLATE"
fi
SUCCESS=1
