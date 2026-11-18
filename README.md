# iasa-infra

Інфраструктура Студради ІПСА на сервері інституту: три Docker-контейнери, у кожен з яких GitHub Actions деплоїть застосунки по SSH.

| Контейнер | Що всередині | Коли працює |
|---|---|---|
| `champ` | сайт + бот хакатону (`champ.iasa.kpi.ua`) | під час хакатону, між ними можна зупиняти |
| `portal` | портал Студради + бот верифікації | постійно |
| `bots` | периферійні боти (мерч, КЯО, …), кожен зі свого репозиторію | постійно |

```
GitHub (push у main)
   └─ Actions ──ssh──▶ контейнер (порт SSH_PORT → 22)
                          └─ deploy-app <app> <repo> <sha>
                                └─ supervisor запускає застосунок на 8000-8009
nginx на сервері ──▶ 127.0.0.1:<HTTP_PORT> ──▶ контейнер:8000
```

На хост сервера Actions не потрапляє: тільки всередину свого контейнера, під користувачем `deploy`.

---

## Для адміністратора сервера

Потрібно один раз:

1. Склонувати репозиторій і заповнити `.env`. Порти взяти з `.env.example` і змінити на ті, що вільні у вас.
2. Запустити:
   ```bash
   docker compose up -d --build
   ```
3. nginx: прокинути домени на HTTP-порти контейнерів (вони слухають тільки `127.0.0.1`):
   ```nginx
   server {
       server_name champ.iasa.kpi.ua;
       # ... ssl як зараз ...
       location / {
           proxy_pass http://127.0.0.1:20080;         # CHAMP_HTTP_PORT
           proxy_set_header Host $host;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
       }
   }
   ```
   Вебхуки Telegram-ботів ідуть через той самий HTTPS домену (наприклад, `location /tg/` → `CHAMP_HOOK_PORT`). Окремий 443 у контейнерах не потрібен.
4. Ззовні мають бути доступні тільки SSH-порти контейнерів (`*_SSH_PORT`): через них заходить GitHub Actions.

Оновити образ (нові SSH-ключі, нові системні пакети): `git pull && docker compose up -d --build`. Застосунки і їхні дані лежать у томах `*-home` і при цьому не губляться.

---

## Для розробників

### Доступ

Свій публічний ключ кладете в `keys/<нік>.pub`, робите PR, після мерджу адмін перезбирає образ. Далі:

```bash
ssh -p <SSH_PORT> deploy@<сервер>
apps                        # статус усіх застосунків у контейнері
apps logs <app> -f          # логи
apps env <app>              # секрети (токени ботів, паролі) → shared/.env, потім перезапуск
apps restart <app>
apps releases <app>         # останні 5 релізів
apps rollback <app>         # повернутися на попередній
```

У `deploy` є `sudo`. Якщо застосунку потрібен системний пакет, додавайте його в `base/Dockerfile`, а не через `apt` руками: ручне встановлення зникне при перезбиранні образу.

### Підключити новий застосунок

1. У репозиторій застосунку додати `deploy/app.conf`:
   ```bash
   START='uvicorn main:app --host 0.0.0.0 --port $PORT'   # як запускати
   PORT=8000                  # порт у контейнері; у bots у кожного бота свій (8000-8003) або без порту для polling
   PERSIST="data"             # каталоги/файли, що мають переживати деплої (БД, завантаження)
   HEALTHCHECK_URL='http://127.0.0.1:$PORT/health'        # необов'язково
   SETUP=''                   # необов'язково: команда після pip install (міграції тощо)
   ```
   Залежності беруться з `requirements.txt`, якщо він є.
2. Скопіювати `templates/deploy.yml` у `.github/workflows/deploy.yml`.
3. У налаштуваннях репозиторію задати змінну `DEPLOY_SSH_PORT`: SSH-порт потрібного контейнера.
4. Секрети (`.env`) один раз внести вручну через `apps env <app>`.

Секрети й змінні на рівні **організації** (налаштувати один раз):

| Назва | Тип | Що це |
|---|---|---|
| `DEPLOY_SSH_KEY` | secret | приватний ключ CI (публічна половина — `keys/github-actions.pub`) |
| `DEPLOY_KNOWN_HOSTS` | secret | вивід `ssh-keyscan -p <порт> <сервер>` для всіх трьох SSH-портів |
| `DEPLOY_HOST` | variable | адреса сервера |

### Що робить `deploy-app`

1. Забирає потрібний коміт у новий каталог `~/apps/<app>/releases/<дата>-<sha>`.
2. Шляхи з `PERSIST` живуть у `~/apps/<app>/shared/` і підставляються симлінками. При першому деплої вони копіюються з репозиторію, далі репозиторій їх не перетирає.
3. Ставить залежності в `~/apps/<app>/venv`, тільки якщо змінився `requirements.txt`.
4. Перемикає `current` на новий реліз і перезапускає застосунок.
5. Перевіряє `HEALTHCHECK_URL` (або що процес живий). Якщо застосунок не піднявся, повертає попередній реліз, і job в Actions падає з логом помилки.

Зберігаються останні 5 релізів.

---

## Структура

```
base/Dockerfile                    образ контейнера
base/rootfs/usr/local/bin/         deploy-app, run-app, apps, entrypoint.sh
base/rootfs/etc/                   конфіги sshd і supervisor
keys/                              публічні SSH-ключі
docker-compose.yml, .env.example   три контейнери і їхні порти
templates/deploy.yml               workflow для репозиторіїв застосунків
.github/workflows/build.yml        CI цього репо: збирає образ і деплоїть тестовий застосунок
```
