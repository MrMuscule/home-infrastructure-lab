# Home Infrastructure Lab

Домашняя инфраструктурная лаборатория для практики Linux, сетей, мониторинга, автоматизации и DevOps.

Всё крутится на Hyper-V на Windows-хосте в сети `LAB-NET` (`10.10.10.0/24`). Приложение (Python API + PostgreSQL) деплоится через GitHub Actions и Ansible, веб-роутер и базовые роли настраиваются Ansible.

## Содержание

- [Архитектура](#архитектура)
- [Хосты](#хосты)
- [Сеть и имена](#сеть-и-имена)
- [Backend API](#backend-api)
- [Ansible](#ansible)
- [CI/CD](#cicd)
- [Terraform](#terraform)
- [Развёртывание](#развёртывание)
- [Известные ограничения и ручные шаги](#известные-ограничения-и-ручные-шаги)
- [Структура репозитория](#структура-репозитория)

## Архитектура

```
                        Windows host (Hyper-V), 10.10.10.254
                                      |
                              LAB-NET 10.10.10.0/24
   +----------------+---------------+---------------+----------------+
   |                |               |               |                |
 web01            web02         monitor01         tf01
 10.10.10.1       10.10.10.2    10.10.10.3        10.10.10.4
 Nginx            API (Docker)  Grafana :3000     VM из Terraform
 reverse proxy    :8082         GitHub runner     (пока без ролей)
 + NAT            PostgreSQL    (Ansible)
 (2-я NIC в       GitHub runner
  Default Switch)
```

Поток запросов:

```
клиент -> web01 (Nginx :80) -> web02:8082 (API в контейнере, порт 8081 внутри)
клиент -> web01 (Nginx :80) -> monitor01:3000 (Grafana)
```

## Хосты

| Хост      | IP           | Роль                                                    | Управляется            |
|-----------|--------------|---------------------------------------------------------|------------------------|
| web01     | 10.10.10.1   | Nginx: reverse proxy, NAT. Второй NIC в `Default Switch` | Ansible (группа `routers`) |
| web02     | 10.10.10.2   | API (Docker Compose), PostgreSQL, GitHub runner         | Ansible (группа `servers`) |
| monitor01 | 10.10.10.3   | Grafana, GitHub runner с Ansible                        | частично (node_exporter) |
| tf01      | 10.10.10.4   | VM, созданная Terraform                                 | только базовые роли    |

Все хосты: Ubuntu 26.04, пользователь `danil`, доступ по SSH-ключу. Ansible подключается под `danil` (`remote_user` в `ansible/ansible.cfg`).

> Адреса и роли описаны в `ansible/inventory.ini`. Если меняется IP — правьте там.

## Сеть и имена

Nginx на web01 маршрутизирует запросы по `Host`-заголовку:

| Имя           | Куда проксируется          | Что там               |
|---------------|----------------------------|-----------------------|
| `web01.lab`   | `http://10.10.10.2:8082`   | API                   |
| `grafana.lab` | `http://10.10.10.3:3000`   | Grafana               |

Чтобы открыть эти имена с клиента, добавьте в hosts-файл клиента (`C:\Windows\System32\drivers\etc\hosts` или `/etc/hosts`) строки:

```
10.10.10.1  web01.lab grafana.lab
```

Конфиг прокси: `ansible/roles/nginx/templates/lab-api.conf.j2`.

## Backend API

Исходники в `backend/`. Простой HTTP-сервер на стандартной библиотеке Python с драйвером `psycopg` для PostgreSQL.

### Эндпоинты

| Метод | Путь          | Описание                                                        | Ответ          |
|-------|---------------|-----------------------------------------------------------------|----------------|
| GET   | `/health`     | Проверка, что сервис жив                                        | `200`          |
| GET   | `/health/db`  | Проверка подключения к PostgreSQL                               | `200` / `503`  |
| POST  | `/telemetry`  | Сохранить метрику в таблицу `telemetry`                         | `201` / `400`  |

Тело запроса для `/telemetry` (JSON):

```json
{
  "server_name": "web02",
  "metric_name": "cpu_load",
  "metric_value": 0.42
}
```

Пример:

```bash
curl http://web01.lab/health
curl -X POST http://web01.lab/telemetry \
  -H "Content-Type: application/json" \
  -d '{"server_name":"web02","metric_name":"cpu_load","metric_value":0.42}'
```

Любой другой путь возвращает `404`.

### Конфигурация

Переменные окружения (читаются из `backend/api.env` на сервере):

| Переменная    | Пример         | Назначение                          |
|---------------|----------------|-------------------------------------|
| `DB_HOST`     | `127.0.0.1`    | Хост PostgreSQL                     |
| `DB_NAME`     | `labdb`        | Имя базы                            |
| `DB_USER`     | `labapp`       | Пользователь БД                     |
| `DB_PASSWORD` | `CHANGE_ME`    | Пароль БД                           |
| `API_HOST`    | `0.0.0.0`      | Адрес, на котором слушает приложение (по умолчанию `0.0.0.0`) |
| `API_PORT`    | `8081`         | Порт приложения (по умолчанию `8081`) |

Шаблон: `backend/api.env.example`. Реальный `api.env` **не коммитится** (см. `.gitignore`).

### Docker

- `backend/Dockerfile` — образ на `python:3.14-slim`, по умолчанию слушает `8081`.
- `backend/compose.yaml` — сервис `home-api`, порт хоста `8082` -> контейнер `8081`, `restart: unless-stopped`.

Локальный запуск (нужна доступная PostgreSQL и заполненный `api.env`):

```bash
cd backend
cp api.env.example api.env   # и заполнить DB_PASSWORD
docker compose up --build
```

### Схема БД

В репозитории схемы нет. Приложение ожидает таблицу `telemetry` с колонками `server_name`, `metric_name`, `metric_value`. Создайте её на web02 вручную (SQL в репозиторий не добавлен).

## Ansible

Каталог `ansible/`. Инвентарь — `inventory.ini`, главный плейбук — `site.yml`.

### Группы инвентаря

| Группа       | Хосты     |
|--------------|-----------|
| `routers`    | web01     |
| `servers`    | web02     |
| `monitoring` | monitor01 |
| `terraform`  | tf01      |
| `lab`        | все выше (объединяет остальные группы) |

### Плейбук `site.yml`

| Play             | Группа     | Роли                  | Что делает |
|------------------|------------|-----------------------|------------|
| Configure lab servers | `lab`  | `common`, `node_exporter` | Базовые пакеты (curl, git, htop, vim), SSH-сервис, Node Exporter |
| Configure web01  | `routers`  | `nginx`               | Установка Nginx, конфиг `lab-api.conf`, отключение default-сайта |
| Deploy API       | `servers`  | `api`                 | Копирование файлов `backend/` в `/home/danil/api`, сборка и запуск контейнера, проверка `/health` |

Роль `api` пересобирает контейнер только если изменились файлы приложения (`when: api_files.changed`).

### Запуск

```bash
cd ansible

# весь лаб
ansible-playbook site.yml

# только один хост
ansible-playbook site.yml --limit web02

# проверка без изменений
ansible-playbook site.yml --check --diff
```

Требования на управляющей машине: Ansible и коллекция `community.docker` (нужна для `docker_compose_v2`), SSH-доступ к хостам по ключу.

## CI/CD

Два workflow в `.github/workflows/`:

1. **`ci.yml` — API CI.** Запускается на push и PR в `main`. Собирает Docker-образ `home-api:test` из `./backend` и проверяет, что он появился. Runner — `ubuntu-latest`.
2. **`deploy.yml` — Deploy API.** Запускается после успешного `API CI` на ветке `main`. Работает на self-hosted runner (`[self-hosted, Linux, X64]`, поднят на monitor01) и выполняет:

   ```bash
   cd ansible
   /usr/bin/ansible-playbook -i inventory.ini site.yml --limit web02
   ```

Поток изменений: push в `main` -> CI собирает образ -> deploy гоняет Ansible на web02 -> контейнер пересобирается и проверяется по `/health`.

## Terraform

Каталог `terraform/`. Провайдер `windsorcli/hyperv` (версия `0.4.0`), backend `local`.

Описывает:

- `lab-web01` — VM поколения 2, 7 vCPU, 4 ГБ RAM, два NIC (`Default Switch` и `LAB-NET`);
- `lab-tf01` — VM поколения 2, 2 vCPU, 4 ГБ RAM, один NIC (`LAB-NET`), загрузка с ISO Ubuntu 26.04, отдельный VHDX на 20 ГБ.

Запуск:

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Файлы состояния (`*.tfstate*`), `tfplan`, `.terraform/` в `.gitignore` и в git не попадают — там могут быть пути и чувствительные данные.

## Развёртывание

Порядок с нуля:

1. **Hyper-V и сеть.** Создать виртуальный свитч `LAB-NET` (внутренний). Поднять VM (вручную или через `terraform apply`).
2. **Базовая настройка ОС.** На каждой VM: пользователь `danil`, `openssh-server`, SSH-ключ. Для web01 — второй NIC в `Default Switch` (выход в интернет, NAT).
3. **Базовые роли и прокси.** С управляющей машины: `ansible-playbook site.yml`.
4. **PostgreSQL на web02.** Установить вручную, создать БД `labdb`, пользователя `labapp`, таблицу `telemetry`.
5. **Файл `api.env` на web02.** Создать из `backend/api.env.example` в `/home/danil/api/api.env` и задать `DB_PASSWORD`. Без него `docker compose` не стартует (см. ниже).
6. **Первый деплой API.** Выполнить `ansible-playbook site.yml --limit web02` или запушить изменения в `main`.
7. **Grafana на monitor01.** Установить вручную, слушает `:3000`.
8. **GitHub runner'ы.** Self-hosted runner на monitor01 (с Ansible) для деплоя.

## Известные ограничения и ручные шаги

- **`api.env` не создаётся Ansible.** Роль `api` копирует только `api.env.example`. Файл `api.env` с реальным паролем нужно положить на web02 вручную.
- **PostgreSQL и Grafana не настраиваются Ansible.** Установлены вручную, в роли их нет.
- **Схема БД не в репозитории.** Таблица `telemetry` создаётся вручную.
- **Hard-coded значения.** Имя сервера в ответе `/health` (`web02-ansible`) и текст в лог-сообщении приложения зашиты в код. Путь `/home/danil/api` и пользователь `danil` — в роли `api`.
- **Terraform: пути в переменных.** Пути к дискам и ISO задаются в `terraform/terraform.tfvars` (шаблон — `terraform.tfvars.example`), в git они не попадают.
- **Пустые каталоги.** `docker/`, `monitoring/`, `nginx/` сейчас пустые (git их не отслеживает) — зарезервированы под будущие конфиги.
- **Секреты.** Никогда не коммитьте `api.env`, ключи SSH, `*.tfstate`. См. `.gitignore`.

## Структура репозитория

```
.
├── .github/workflows/
│   ├── ci.yml                 # сборка Docker-образа API
│   └── deploy.yml             # деплой через Ansible на web02
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.ini         # хосты и группы
│   ├── site.yml              # главный плейбук
│   └── roles/
│       ├── common/           # базовые пакеты, SSH
│       ├── node_exporter/    # Prometheus Node Exporter
│       ├── nginx/            # reverse proxy на web01
│       └── api/              # деплой API на web02
├── backend/
│   ├── app.py                # HTTP API + psycopg
│   ├── Dockerfile
│   ├── compose.yaml
│   ├── requirements.txt
│   └── api.env.example
├── terraform/                # VM в Hyper-V (не под git)
├── docker/                   # пусто
├── monitoring/               # пусто
├── nginx/                    # пусто
└── README.md
```
