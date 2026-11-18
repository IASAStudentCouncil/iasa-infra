#!/bin/bash
# Підготовка контейнера при кожному старті, далі — supervisord (sshd + застосунки).
set -euo pipefail

# 1. Ключі хоста SSH: генеруються один раз і живуть у томі, щоб відбиток не мінявся
for t in ed25519 rsa; do
    f="/etc/ssh/host_keys/ssh_host_${t}_key"
    if [ ! -f "$f" ]; then
        if [ "$t" = rsa ]; then
            ssh-keygen -q -t rsa -b 4096 -N "" -f "$f"
        else
            ssh-keygen -q -t ed25519 -N "" -f "$f"
        fi
    fi
done
chmod 600 /etc/ssh/host_keys/*_key

# 2. Дозволені ключі: усі keys/*.pub з образу + змінна AUTHORIZED_KEYS (по одному ключу на рядок)
mkdir -p /etc/ssh/authorized_keys
{
    find /etc/iasa/keys -maxdepth 1 -name '*.pub' -type f -exec cat {} + 2>/dev/null || true
    printf '%s\n' "${AUTHORIZED_KEYS:-}"
} | grep -E '^(ssh-|ecdsa-|sk-)' | sort -u > /etc/ssh/authorized_keys/deploy || true
chown root:root /etc/ssh/authorized_keys /etc/ssh/authorized_keys/deploy
chmod 755 /etc/ssh/authorized_keys
chmod 644 /etc/ssh/authorized_keys/deploy
if [ ! -s /etc/ssh/authorized_keys/deploy ]; then
    echo "WARNING: немає жодного SSH-ключа — зайти в контейнер не вийде" >&2
fi

# 3. Робочі каталоги користувача deploy (том міг бути порожнім)
install -d -o deploy -g deploy /home/deploy/apps /home/deploy/supervisor /home/deploy/logs /home/deploy/run

# 4. Ім'я контейнера в запрошенні shell, щоб не плутати champ/portal/bots
if [ -n "${CONTAINER_NAME:-}" ] && ! grep -q IASA_PS1 /home/deploy/.bashrc 2>/dev/null; then
    echo "export PS1='\\u@${CONTAINER_NAME}:\\w\\$ ' # IASA_PS1" >> /home/deploy/.bashrc
    chown deploy:deploy /home/deploy/.bashrc
fi

# Змінні середовища контейнера (TZ, CONTAINER_NAME) — для SSH-сесій теж
env | grep -E '^(TZ|CONTAINER_NAME)=' > /etc/environment || true

exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
