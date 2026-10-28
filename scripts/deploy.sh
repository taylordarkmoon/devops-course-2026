#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                       # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

fail() { echo "deploy: ОШИБКА: $*" >&2; exit 1; }

# 1. Разбор аргумента --dry-run
DRY_RUN=false
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN=true ;;
    *)         fail "неизвестный аргумент '$1'. Использование: scripts/deploy.sh [--dry-run]" ;;
esac

# 2. Проверки по требованиям 4 и 5
[[ -f "${LOCAL_DIR}index.html" ]] \
    || fail "нет файла site/index.html — доставка отменена (--delete удалил бы главную страницу с сервера)"
if ! git -C "$REPO_ROOT" diff --quiet || ! git -C "$REPO_ROOT" diff --cached --quiet \
   || [[ -n "$(git -C "$REPO_ROOT" ls-files --others --exclude-standard -- site/)" ]]; then
    fail "в репозитории есть незафиксированные изменения — сначала выполните git commit"
fi
COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

# 3. Синхронизация каталога ${LOCAL_DIR} на ${REMOTE}:${REMOTE_DIR}:
#    одно SSH-соединение (только rsync), без интерактивного запроса пароля
RSYNC_OPTS=(-avz --delete --chmod=D755,F644 -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if $DRY_RUN; then RSYNC_OPTS+=(--dry-run); fi
echo "deploy: коммит ${COMMIT} -> ${REMOTE}:${REMOTE_DIR}$($DRY_RUN && echo ' (пробный запуск)')"
rsync "${RSYNC_OPTS[@]}" "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/" \
    || fail "синхронизация не выполнена (rsync/ssh)"

# 4. При --dry-run — завершение с кодом 0 без проверки доступности
if $DRY_RUN; then
    echo "deploy: пробный запуск завершён, состояние сервера не изменено"
    exit 0
fi

# 5. Проверка доступности ${SITE_URL} с проверкой сертификата и корректный код возврата
curl -fsS --max-time 10 --cacert "$CA_CERT" -o /dev/null "$SITE_URL" \
    || fail "ресурс ${SITE_URL} недоступен после доставки"
echo "deploy: успешно, доставлен коммит ${COMMIT}"
