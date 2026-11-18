# Базовий "контейнер-сервер" Студради ІПСА.
# Усередині: SSH (тільки за ключем), Python 3.12, git, supervisor і скрипт deploy-app,
# через який GitHub Actions деплоїть застосунки.
FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openssh-server supervisor git curl ca-certificates sudo tini tzdata less nano procps \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash --uid 1000 deploy \
    && echo 'deploy ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/deploy \
    && chmod 0440 /etc/sudoers.d/deploy \
    && rm -f /etc/ssh/ssh_host_* \
    && mkdir -p /run/sshd /etc/ssh/host_keys

ENV TZ=Europe/Kyiv

COPY base/rootfs/ /
COPY keys/ /etc/iasa/keys/

RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/deploy-app /usr/local/bin/run-app /usr/local/bin/apps \
    && chmod 0644 /etc/ssh/sshd_config.d/iasa.conf

# 22 — SSH, 8000-8009 — застосунки (сайти, вебхуки ботів)
EXPOSE 22 8000-8009

# /home/deploy — застосунки, їхні дані й venv; /etc/ssh/host_keys — щоб відбиток сервера не мінявся
VOLUME ["/home/deploy", "/etc/ssh/host_keys"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
