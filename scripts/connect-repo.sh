#!/usr/bin/env bash
# connect-repo.sh <repo> <champ|portal|bots>
#
# Підключає репозиторій застосунку до CI/CD: задає в ньому всі секрети й змінні,
# потрібні workflow з templates/deploy.yml (або з bot-template).
# Працює однаково для публічних і приватних репо (секрети задаються на рівні репо).
#
# Значення беруться з локального файлу девопса (за замовчуванням ~/.config/iasa-deploy.env,
# зразок — scripts/deploy.env.example). Цей файл містить секрети: chmod 600, у git не класти.
set -euo pipefail

ORG=IASAStudentCouncil
CONF=${IASA_DEPLOY_CONF:-$HOME/.config/iasa-deploy.env}

[ $# -eq 2 ] || { echo "використання: $0 <repo> <champ|portal|bots>" >&2; exit 1; }
REPO=$ORG/$1 CONTAINER=$2
[ -f "$CONF" ] || { echo "немає $CONF — скопіюйте scripts/deploy.env.example і заповніть" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONF"

case $CONTAINER in
    champ)  PORT=${CHAMP_SSH_PORT:-} ;;
    portal) PORT=${PORTAL_SSH_PORT:-} ;;
    bots)   PORT=${BOTS_SSH_PORT:-} ;;
    *) echo "контейнер має бути champ, portal або bots" >&2; exit 1 ;;
esac

gh repo view "$REPO" --json name >/dev/null

echo "→ $REPO (контейнер $CONTAINER)"
gh secret set DEPLOY_SSH_KEY --repo "$REPO" < "${DEPLOY_SSH_KEY_FILE/#\~/$HOME}"

if [ -n "${TG_BOT_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ]; then
    printf '%s' "$TG_BOT_TOKEN" | gh secret set TG_BOT_TOKEN --repo "$REPO"
    gh secret set TG_CHAT_ID --repo "$REPO" --body "$TG_CHAT_ID"
    if [ -n "${TG_THREAD_ID:-}" ]; then
        gh secret set TG_THREAD_ID --repo "$REPO" --body "$TG_THREAD_ID"
    fi
fi

if [ -n "${DEPLOY_HOST:-}" ] && [ -n "$PORT" ]; then
    known=$(ssh-keyscan -p "$PORT" "$DEPLOY_HOST" 2>/dev/null)
    [ -n "$known" ] || { echo "ssh-keyscan не достукався до $DEPLOY_HOST:$PORT — контейнер запущено?" >&2; exit 1; }
    printf '%s\n' "$known" | gh secret set DEPLOY_KNOWN_HOSTS --repo "$REPO"
    gh variable set DEPLOY_HOST --repo "$REPO" --body "$DEPLOY_HOST"
    gh variable set DEPLOY_SSH_PORT --repo "$REPO" --body "$PORT"
    echo "✓ готово: наступний push у main задеплоїться в $CONTAINER"
else
    echo "✓ секрети задано; DEPLOY_HOST/порт ще не відомі — деплой поки пропускатиметься."
    echo "  Коли сервер буде готовий, заповніть їх у $CONF і запустіть скрипт ще раз."
fi
