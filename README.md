# infra-monitoring-project

[![CI](https://github.com/Krams74a/infra-monitoring-project/actions/workflows/ci.yml/badge.svg)](https://github.com/Krams74a/infra-monitoring-project/actions/workflows/ci.yml)

Инфраструктура мониторинга для простого echo-API: проверка доступности, анализ логов, контейнеризированный стек и CI/CD.

Работа ведется в ветке `feature/monitoring`, в `main` изменения попадают только через Pull Request.

## Состав проекта

```
.
├── check_api.sh              # проверка доступности API по коду ответа
├── analyze_logs.sh           # генерация и анализ access.log
├── docker-compose.yml        # стек api + proxy
├── nginx/
│   └── default.conf          # конфиг обратного прокси
├── .github/workflows/ci.yml  # пайплайн GitHub Actions
├── .gitignore
└── .gitattributes            # LF-окончания строк для всех текстовых файлов
```

## Требования

- bash 4+, curl, grep, awk, sed, sort, uniq
- Docker с плагином Compose v2 (`docker compose`) или отдельный `docker-compose`
- Git

## Быстрый старт

```bash
git clone https://github.com/Krams74a/infra-monitoring-project.git
cd infra-monitoring-project
chmod +x check_api.sh analyze_logs.sh
```

## check_api.sh – мониторинг доступности API

```
./check_api.sh <URL>
```

Скрипт проверяет URL регулярным выражением, делает запрос через `curl` с таймаутом 10 секунд и сравнивает код ответа с ожидаемым 200.

| Ситуация | Вывод | Код возврата |
|---|---|---|
| сервер ответил 200 | `API доступен` | 0 |
| сервер ответил другим кодом | `API недоступен, код ответа: XXX` | 1 |
| соединиться не удалось | `API недоступен, код ответа: 000` | 1 |
| нет аргумента или URL некорректный | сообщение об ошибке в stderr | 1 |

Пример:

```
$ ./check_api.sh https://httpbin.org/status/200
API доступен
$ echo $?
0

$ ./check_api.sh https://httpbin.org/status/404
API недоступен, код ответа: 404
$ echo $?
1
```

## analyze_logs.sh – анализ логов

```
./analyze_logs.sh [-n СТРОК] [-f ФАЙЛ] [-s] [-h]
```

| Ключ | Назначение | По умолчанию |
|---|---|---|
| `-n` | сколько строк сгенерировать, не меньше 300 | 300 |
| `-f` | путь к файлу лога | `access.log` |
| `-s` | не генерировать лог, а проанализировать существующий | – |
| `-h` | справка | – |

Скрипт генерирует лог с записями вида

```
192.168.1.10 - - [15/Aug/2026:10:15:32] "GET /api/users HTTP/1.1" 200
```

и считает по нему статистику:

- общее количество запросов – `grep -cE` по регулярному выражению IPv4-адреса в начале строки;
- топ-3 IP-адресов – `grep -oE` извлекает адреса, дальше `sort | uniq -c | sort -rn` и `awk`;
- ответы 4xx и 5xx – `awk` проверяет последнее поле строки регулярными выражениями `^4[0-9][0-9]$` и `^5[0-9][0-9]$`;
- разбивка по HTTP-методам – `sed -E` вырезает метод из строки запроса.

Для генерации зафиксировано зерно `RANDOM`, поэтому лог и статистика одинаковы от запуска к запуску.

```
$ ./analyze_logs.sh
Сгенерирован файл access.log: 300 строк

=== Анализ лога: access.log ===
Общее количество запросов: 300

Топ-3 IP-адресов по числу запросов:
  1. 192.168.1.10    81
  2. 10.0.0.5        60
  3. 172.16.0.23     44

Запросы с кодами ошибок:
  4xx (ошибки клиента): 68
  5xx (ошибки сервера): 34

Запросы по HTTP-методам:
  GET     168
  POST    84
  DELETE  26
  PUT     22
```

## Docker Compose – стек мониторинга

```
клиент ──> proxy (nginx:alpine, порт 80) ──> api (hashicorp/http-echo, порт 8080)
           └──────────── сеть monitoring (bridge) ────────────┘
```

- `api` отвечает текстом «Monitoring Service Active» на порту 8080. Наружу порт не публикуется, сервис доступен только внутри сети `monitoring`.
- `proxy` публикует порт 80 и передает запросы на `api:8080`. Имя `api` резолвит встроенный DNS Docker. Для прокси настроен healthcheck.

Запуск и проверка:

```bash
docker compose up -d
curl http://localhost:80        # Monitoring Service Active
./check_api.sh http://localhost:80
docker compose ps
```

Остановка:

```bash
docker compose down
```

С Compose v1 команды те же, только через дефис: `docker-compose up -d`, `docker-compose ps`.

## CI/CD – GitHub Actions

Пайплайн `.github/workflows/ci.yml` запускается при Pull Request в `main`, при пуше в `main` и вручную. В нем две задачи.

**bash-scripts**
1. Проверка синтаксиса: `bash -n check_api.sh` и `bash -n analyze_logs.sh`.
2. Статический анализ ShellCheck.
3. `./check_api.sh https://httpbin.org/status/200` с ожиданием кода 0. httpbin.org иногда отвечает 5xx, поэтому дается три попытки.
4. `check_api.sh` на ответе 404, на недоступном порту, на некорректном URL и без аргументов с ожиданием кода 1.
5. Генерация лога через `analyze_logs.sh` и проверка, что в нем не меньше 300 строк.

**docker-compose**
1. Проверка файла: `docker compose config`.
2. `docker compose up -d --wait`.
3. Запрос через прокси: `check_api.sh http://localhost:80` и проверка текста «Monitoring Service Active».
4. `docker compose down`.

## Git workflow

- `main` – защищенная ветка: прямой пуш запрещен, слияние только через Pull Request с зеленым CI.
- `feature/monitoring` – рабочая ветка, в ней ведется вся разработка.
- По завершении работы открывается Pull Request из `feature/monitoring` в `main` с описанием изменений.

## Деплой на удаленный сервер по SSH

В примерах сервер – `deploy@203.0.113.10`, проект разворачивается в `~/infra-monitoring-project`.

### 1. Генерация SSH-ключа

На рабочей машине создаем пару ключей ed25519:

```bash
ssh-keygen -t ed25519 -C "deploy@infra-monitoring" -f ~/.ssh/id_ed25519
```

Закрытый ключ `~/.ssh/id_ed25519` остается на машине и никуда не передается. На сервер копируется только открытый ключ `~/.ssh/id_ed25519.pub`.

### 2. Копирование открытого ключа на сервер

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub deploy@203.0.113.10
```

Команда один раз спросит пароль и допишет ключ в `~/.ssh/authorized_keys` на сервере. В Windows `ssh-copy-id` нет, там то же самое делается так (PowerShell):

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh deploy@203.0.113.10 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Проверяем, что вход работает без пароля:

```bash
ssh deploy@203.0.113.10 'hostname && whoami'
```

Чтобы не писать адрес каждый раз, удобно добавить запись в `~/.ssh/config`:

```
Host monitoring
    HostName 203.0.113.10
    User deploy
    IdentityFile ~/.ssh/id_ed25519
```

После этого везде можно писать просто `ssh monitoring`. Когда вход по ключу настроен, на сервере стоит отключить вход по паролю: `PasswordAuthentication no` в `/etc/ssh/sshd_config` и `sudo systemctl reload ssh`.

### 3. Передача проекта через scp

Упаковываем проект без `.git` и логов, копируем архив и распаковываем на сервере:

```bash
tar -czf /tmp/infra-monitoring.tar.gz --exclude=.git --exclude='*.log' .
scp /tmp/infra-monitoring.tar.gz monitoring:/tmp/
ssh monitoring 'mkdir -p ~/infra-monitoring-project \
  && tar -xzf /tmp/infra-monitoring.tar.gz -C ~/infra-monitoring-project \
  && rm /tmp/infra-monitoring.tar.gz'
```

Отдельные файлы или каталог можно скопировать и без архива:

```bash
scp check_api.sh analyze_logs.sh docker-compose.yml monitoring:~/infra-monitoring-project/
scp -r nginx monitoring:~/infra-monitoring-project/
```

### 4. Передача через tar + ssh

Тот же результат одной командой, без временного файла: `tar` пишет архив в stdout, `ssh` передает поток на сервер, где он сразу распаковывается.

```bash
tar -czf - --exclude=.git --exclude='*.log' . \
  | ssh monitoring 'mkdir -p ~/infra-monitoring-project && tar -xzf - -C ~/infra-monitoring-project'
```

### 5. Запуск на сервере

```bash
ssh monitoring 'cd ~/infra-monitoring-project \
  && chmod +x check_api.sh analyze_logs.sh \
  && docker compose pull \
  && docker compose up -d \
  && ./check_api.sh http://localhost:80'
```

Последняя команда сразу проверяет, что прокси отвечает. Если она вернула код 1, смотрим логи:

```bash
ssh monitoring 'cd ~/infra-monitoring-project && docker compose ps && docker compose logs --tail 50'
```
