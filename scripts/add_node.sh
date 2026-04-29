#!/usr/bin/env bash
# add_node.sh — добавить новую EU-ноду в инвентарь и раскатать через ansible.
#
# Этот скрипт живёт на master-ноде (Болгария) рядом с клоном этого репозитория.
# Telegram-бот вызывает его по SSH (см. handlers/admin_add_node.py в bot_remna).
# Все аргументы — обязательные, кроме помеченных как [optional].
#
# Использование:
#   ./scripts/add_node.sh \
#       --name eu_node_3 \
#       --address node3.example.com \
#       --ssh-port 22 \
#       --node-port 3743 \
#       --bridge-sni www.microsoft.com \
#       --country NL
#
# Поведение:
#   1. Проверяет аргументы и что нода с таким именем ещё не в inventory.ini.
#   2. (опционально) Если задана SSHPASS_INITIAL — копирует pubkey master через
#      sshpass+ssh-copy-id на root@address:ssh-port.
#   3. Добавляет блок в inventory.ini под секцией [eu_nodes].
#   4. Делает ansible -m ping для новой ноды; при ошибке бросает с понятным
#      сообщением.
#   5. Запускает ansible-playbook deploy.yml -l <name>.
#
# Скрипт идемпотентен в части inventory: если запись уже существует, шаг 3
# пропускается. Сам ansible-playbook идемпотентен по построению.

set -euo pipefail

# --- Парсим аргументы ---
NAME=""
ADDRESS=""
SSH_PORT=""
NODE_PORT=""
BRIDGE_SNI=""
COUNTRY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)        NAME="$2";        shift 2;;
        --address)     ADDRESS="$2";     shift 2;;
        --ssh-port)    SSH_PORT="$2";    shift 2;;
        --node-port)   NODE_PORT="$2";   shift 2;;
        --bridge-sni)  BRIDGE_SNI="$2";  shift 2;;
        --country)     COUNTRY="$2";     shift 2;;
        -h|--help)
            cat <<'HELP'
add_node.sh — добавить новую EU-ноду в инвентарь и раскатать через ansible.

Использование:
  ./scripts/add_node.sh \
      --name eu_node_3 \
      --address node3.example.com \
      --ssh-port 22 \
      --node-port 3743 \
      --bridge-sni www.microsoft.com \
      --country NL

Опционально:
  SSHPASS_INITIAL=пароль  ./scripts/add_node.sh ...
      Если задано, скопирует master pubkey на новую ноду через
      sshpass+ssh-copy-id перед ansible-ping.

Шаги:
  1. Валидирует аргументы.
  2. Дописывает запись в [eu_nodes] секцию inventory.ini (идемпотентно).
  3. (опц.) Копирует SSH-ключ master на новую ноду.
  4. ansible -m ping для проверки доступности.
  5. ansible-playbook deploy.yml -l NAME.
HELP
            exit 0
            ;;
        *)
            echo "[add_node] Неизвестный аргумент: $1" >&2
            exit 2
            ;;
    esac
done

for required in NAME ADDRESS SSH_PORT NODE_PORT BRIDGE_SNI COUNTRY; do
    if [[ -z "${!required}" ]]; then
        echo "[add_node] Не задан обязательный аргумент: --${required,,}" >&2
        exit 2
    fi
done

if ! [[ "$NAME" =~ ^[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]$ ]]; then
    echo "[add_node] Имя ноды должно быть 3-32 символа: a-z 0-9 '-' '_'" >&2
    exit 2
fi
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
    echo "[add_node] --ssh-port должен быть числом 1..65535" >&2
    exit 2
fi
if ! [[ "$NODE_PORT" =~ ^[0-9]+$ ]] || (( NODE_PORT < 1 || NODE_PORT > 65535 )); then
    echo "[add_node] --node-port должен быть числом 1..65535" >&2
    exit 2
fi
if ! [[ "$COUNTRY" =~ ^[A-Z]{2}$ ]]; then
    echo "[add_node] --country должен быть 2 латинскими буквами в верхнем регистре" >&2
    exit 2
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INVENTORY="$REPO_DIR/inventory.ini"
PLAYBOOK="$REPO_DIR/deploy.yml"

if [[ ! -f "$INVENTORY" ]]; then
    echo "[add_node] inventory.ini не найден: $INVENTORY" >&2
    exit 1
fi
if [[ ! -f "$PLAYBOOK" ]]; then
    echo "[add_node] deploy.yml не найден: $PLAYBOOK" >&2
    exit 1
fi

echo "[add_node] === Параметры ==="
echo "[add_node] name=$NAME address=$ADDRESS ssh_port=$SSH_PORT"
echo "[add_node] node_port=$NODE_PORT bridge_sni=$BRIDGE_SNI country=$COUNTRY"
echo "[add_node] repo_dir=$REPO_DIR"

# --- 1. Проверяем что ноды с таким именем ещё нет в inventory ---
if grep -E "^${NAME}\s" "$INVENTORY" >/dev/null 2>&1; then
    echo "[add_node] В $INVENTORY уже есть запись с именем '$NAME'. Пропускаю append." >&2
else
    # Найдём строку с [eu_nodes] и допишем после последней строки этой секции
    # (до пустой строки или следующей секции).
    if ! grep -E "^\[eu_nodes\]" "$INVENTORY" >/dev/null; then
        echo "[add_node] В $INVENTORY нет секции [eu_nodes]." >&2
        exit 1
    fi
    new_line="${NAME} ansible_host=${ADDRESS} ansible_user=root ansible_port=${SSH_PORT} bridge_sni=${BRIDGE_SNI} node_port=${NODE_PORT} country_code=${COUNTRY}"
    echo "[add_node] Добавляю в inventory.ini:"
    echo "[add_node]   $new_line"
    # awk: пройти до строки [eu_nodes], потом дописать ПЕРЕД следующей секцией или EOF
    tmp_inv="$(mktemp)"
    awk -v new_line="$new_line" '
        BEGIN { in_eu = 0; written = 0 }
        /^\[eu_nodes\]/ { print; in_eu = 1; next }
        in_eu && !written && (/^\[/ || NF == 0) {
            print new_line
            written = 1
            in_eu = 0
        }
        { print }
        END {
            if (in_eu && !written) print new_line
        }
    ' "$INVENTORY" > "$tmp_inv"
    mv "$tmp_inv" "$INVENTORY"
fi

# --- 2. (опционально) Копируем master pubkey на новую ноду ---
if [[ -n "${SSHPASS_INITIAL:-}" ]]; then
    if ! command -v sshpass >/dev/null; then
        echo "[add_node] SSHPASS_INITIAL задан, но sshpass не установлен." >&2
        echo "[add_node] Установи: apt-get install -y sshpass" >&2
        exit 1
    fi
    if ! command -v ssh-copy-id >/dev/null; then
        echo "[add_node] ssh-copy-id не найден (apt-get install -y openssh-client)." >&2
        exit 1
    fi
    echo "[add_node] Копирую SSH-ключ master → root@${ADDRESS}:${SSH_PORT}…"
    SSHPASS="$SSHPASS_INITIAL" sshpass -e ssh-copy-id \
        -o StrictHostKeyChecking=accept-new \
        -p "$SSH_PORT" \
        "root@${ADDRESS}"
    unset SSHPASS_INITIAL
fi

# --- 3. ansible ping ---
echo "[add_node] Проверка SSH через ansible -m ping…"
if ! ansible "$NAME" -i "$INVENTORY" -m ping; then
    cat <<EOF >&2
[add_node] Не удалось достучаться до ноды через ansible.
Возможные причины:
  - SSH-ключ master не установлен на новой ноде (передай SSHPASS_INITIAL=пароль_root)
  - Брандмауэр блокирует ssh-порт ${SSH_PORT}
  - Хост ${ADDRESS} ещё не разрезолвлен / нода не поднята
Запись в inventory оставлена для последующих попыток.
EOF
    exit 1
fi

# --- 4. ansible-playbook ---
echo "[add_node] Запуск ansible-playbook deploy.yml -l ${NAME}…"
ansible-playbook "$PLAYBOOK" -i "$INVENTORY" -l "$NAME"

echo "[add_node] ✅ Нода ${NAME} успешно раскатана."
