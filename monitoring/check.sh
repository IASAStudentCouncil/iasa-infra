#!/usr/bin/env bash
# Перевіряє сайти з monitoring/targets.txt.
# Стан між запусками — відкриті issues з міткою "outage" (одна на сайт):
#   сайт ліг і issue ще нема  -> відкрити issue + 🔴 у Telegram
#   сайт живий і issue є      -> закрити issue  + 🟢 у Telegram
# Повідомлення йдуть тільки при зміні стану.
set -uo pipefail

TARGETS=${TARGETS:-monitoring/targets.txt}
ATTEMPTS=${ATTEMPTS:-3}
RETRY_DELAY=${RETRY_DELAY:-10}
LABEL=outage

tg() {
    [ -n "${TG_BOT_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ] || return 0
    # алерти йдуть в окрему гілку форуму, якщо задано TG_ALERT_THREAD_ID; інакше — туди ж, куди CI
    local thread=${TG_ALERT_THREAD_ID:-${TG_THREAD_ID:-}} args=()
    [ -n "$thread" ] && args+=(-d message_thread_id="$thread")
    curl -sS -o /dev/null -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
        -d chat_id="$TG_CHAT_ID" -d parse_mode=HTML -d disable_web_page_preview=true \
        "${args[@]}" --data-urlencode text="$1" || echo "::warning::Telegram недоступний"
}

# повертає HTTP-код (000 — немає з'єднання); успіх — будь-який 2xx/3xx
probe() {
    curl -sS -o /dev/null -L --max-time 15 -w '%{http_code}' "$1" 2>/dev/null || true
}

gh label create "$LABEL" --color B60205 --description "Сайт недоступний (моніторинг)" >/dev/null 2>&1 || true
open_issues=$(gh issue list --label "$LABEL" --state open --limit 100 --json number,title,createdAt)

while read -r name url <&3 || [ -n "${name:-}" ]; do
    [[ -z "${name:-}" || $name == \#* ]] && continue
    code=000
    for i in $(seq 1 "$ATTEMPTS"); do
        code=$(probe "$url")
        [[ $code =~ ^[23] ]] && break
        [ "$i" -lt "$ATTEMPTS" ] && sleep "$RETRY_DELAY"
    done
    title="🔴 $name недоступний"
    issue=$(jq -r --arg t "$title" '.[] | select(.title==$t) | .number' <<<"$open_issues" | head -n1)

    if [[ $code =~ ^[23] ]]; then
        echo "UP    $name ($code) $url"
        if [ -n "$issue" ]; then
            since=$(jq -r --arg t "$title" '.[] | select(.title==$t) | .createdAt' <<<"$open_issues" | head -n1)
            mins=$(( ( $(date +%s) - $(date -d "$since" +%s) ) / 60 ))
            gh issue close "$issue" --comment "🟢 Відновлено $(date -u '+%Y-%m-%d %H:%M UTC'), HTTP $code. Лежав ~${mins} хв." >/dev/null
            tg "🟢 <b>$name</b> знову працює (лежав ~${mins} хв)
$url"
        fi
    else
        echo "DOWN  $name ($code) $url"
        if [ -z "$issue" ]; then
            new=$(gh issue create --label "$LABEL" --title "$title" \
                --body "Моніторинг не достукався до $url ($ATTEMPTS спроби, остання відповідь: HTTP $code).
Перша помилка: $(date -u '+%Y-%m-%d %H:%M UTC'). Issue закриється автоматично, коли сайт підніметься.

Run: ${RUN_URL:-}")
            tg "🔴 <b>$name</b> недоступний (HTTP $code)
$url
<a href=\"$new\">issue</a>${RUN_URL:+ · <a href=\"$RUN_URL\">run</a>}"
        fi
    fi
done 3< "$TARGETS"

# run завжди зелений: тривогу піднімають issue і Telegram, а червоні scheduled-runs
# спамили б листами кожні 10 хв, поки сайт лежить.
exit 0
