# 🚀 Remnawave + Xray Bridge Deployment

Этот проект автоматизирует развертывание VPN-инфраструктуры "Матрёшка": европейские ноды Remnawave маскируются через российский сервер в Яндекс.Облаке (Hiddify).

Проект полностью рефакторизован под **модульную архитектуру ролей Ansible** и использует **Ansible Vault** для безопасного хранения всех чувствительных данных (секретных ключей нод, токенов API и паролей пользователей Telemt).

---

## 📋 Требования (на управляющей машине / ПК)
1. **Python 3** и **Ansible** (`sudo apt install ansible` / `pip install ansible-core`).
2. **SSH-доступ** по ключам ко всем серверам.
3. Установленные коллекции Ansible:
   ```bash
   ansible-galaxy collection install community.docker community.general
   ```
4. **Файл `.vault-pass`** в корневой директории проекта, содержащий пароль для расшифровки Ansible Vault.

---

## 📂 Структура проекта

* `ansible.cfg` — конфигурационный файл Ansible (настроен дефолтный инвентарь и путь к `.vault-pass`).
* `inventory.ini` — список серверов (очищен от секретов).
* `deploy.yml` — основной плейбук, вызывающий соответствующие роли.
* `.vault-pass` — локальный файл с паролем дешифрации (добавлен в `.gitignore`, никогда не коммитится!).
* `group_vars/all/` — глобальные переменные:
  * `vars.yml` — нечувствительные настройки (домен, UUID профилей панели).
  * `vault.yml` — зашифрованный Ansible Vault файл с API-токеном и паролями Telemt.
* `host_vars/<hostname>/` — индивидуальные настройки хостов:
  * `vars.yml` — нечувствительные параметры и ссылки на vault.
  * `vault.yml` — зашифрованный `node_secret` хоста.
* `roles/` — папка с ролями:
  * `docker` — установка Docker.
  * `firewall` — настройка UFW/Firewalld.
  * `haproxy` — установка и настройка HAProxy для worker-нод.
  * `telemt` — установка официального сервиса Telemt (из GitHub релизов) и генерация системного юнита.
  * `remnanode` — регистрация нод в панели, генерация Reality-ключей, развёртывание контейнеров Remnanode и Bridge-receiver.
  * `yandex_bridge` — настройка bridge-sender, интеграция Matrix/Bridge роутинга в Hiddify, отключение DPI-протоколов.
* `scripts/add_node.sh` — хелпер-скрипт для добавления новых нод через Telegram-бота или вручную.

---

## 🛠 Настройка перед запуском

### 1. Создайте `.vault-pass` в корне проекта
Запишите ваш секретный пароль для Vault:
```bash
echo "ваш_пароль_vault" > .vault-pass
```

### 2. Заполните `inventory.ini`
Укажите адреса и параметры ваших нод (свойства `node_secret` здесь больше указывать не нужно!):
```ini
[yandex]
yandex_node ansible_host=IP_ЯНДЕКСА ansible_user=andrwy

[eu_nodes]
bulgaria_main ansible_host=femboyhooters.kawaiinekos.cfd ansible_user=root bridge_sni=www.microsoft.com is_main=true node_port=3743
;eu_node_2     ansible_host=caffeinated.kawaiinekos.cfd ansible_user=root bridge_sni=drive.google.com node_port=1488
```

### 3. Настройте глобальные переменные (`group_vars/all/`)
Все чувствительные данные шифруются в Vault. 
Для создания или редактирования зашифрованных файлов используйте команду:
```bash
# Редактирование глобальных секретов
ansible-vault edit group_vars/all/vault.yml
```
Пример содержимого `group_vars/all/vault.yml` (после расшифровки):
```yaml
---
vault_remnawave_api_token: "ВАШ_API_TOKEN_ИЗ_АДМИНКИ"
vault_telemt_users:
  docker: "ключ_пользователя_docker_32_символа"
  l1ttlewizard: "ключ_пользователя_l1ttlewizard_32_символа"
```

### 4. Настройте секреты хостов (`host_vars/`)
Каждая нода имеет свой `node_secret` (полученный из Remnawave), который хранится в `host_vars/<hostname>/vault.yml` в зашифрованном виде.
```bash
# Редактирование секрета для конкретного хоста
ansible-vault edit host_vars/bulgaria_main/vault.yml
```
Пример содержимого `host_vars/bulgaria_main/vault.yml` (после расшифровки):
```yaml
---
vault_node_secret: "eyJub2RlQ2VydF..."
```

---

## 🚀 Запуск деплоя

Благодаря конфигурации в `ansible.cfg` запуск выполняется одной короткой командой (пароль подтянется автоматически из файла `.vault-pass`):

```bash
ansible-playbook deploy.yml
```

### Что делает плейбук:
1. **На европейских нодах (Worker-ноды):**
   * Устанавливает и запускает Docker.
   * Настраивает брандмауэр UFW (Debian) или Firewalld (RedHat), открывая порты 22 и 443.
   * Устанавливает и конфигурирует HAProxy для маршрутизации трафика Reality/Telemt.
   * Регистрирует ноду в Remnawave по API (если её ещё нет в панели).
   * Автоматически генерирует UUID и пары ключей Reality (`x25519`), запуская `bridge-receiver`.
2. **На главной ноде (Bulgaria Main - `is_main=true`):**
   * Пропускает установку Docker, Firewall и HAProxy (из соображений безопасности ваших ручных конфигов).
   * Собирает факты о ключах Reality для Yandex-моста.
3. **На всех нодах (включая Bulgaria Main):**
   * Устанавливает официальный бинарь Telemt через systemd-сервис и обновляет пользователей на основе зашифрованного списка из Vault.
4. **На сервере Яндекса (Hiddify):**
   * Разворачивает `bridge-sender` (подключает выходные туннели Reality на все европейские ноды).
   * Интегрирует Matrix (HTTP/QUIC) и Bridge (TCP SNI) бэкенды в HAProxy (.pj2 файлы Hiddify-менеджера).
   * Отключает DPI-палевные протоколы в базе данных Hiddify и применяет конфигурацию.

---

## ➕ Добавление новой ноды (через бот или вручную)

Скрипт `scripts/add_node.sh` используется для полуавтоматического добавления новых нод в инфраструктуру.

```bash
# Запуск с управляющей/master ноды:
./scripts/add_node.sh \
    --name eu_node_3 \
    --address node3.example.com \
    --ssh-port 22 \
    --node-port 3743 \
    --bridge-sni www.microsoft.com \
    --country NL
```

### Алгоритм работы скрипта:
1. Проверяет наличие `.vault-pass` в корне проекта.
2. Проверяет аргументы и идемпотентно дописывает ноду в `inventory.ini` под секцию `[eu_nodes]`.
3. (Опционально) Копирует SSH-ключ, если передан пароль в переменной `SSHPASS_INITIAL`.
4. Делает тестовый пинг через Ansible.
5. Запускает деплой для новой ноды.
6. **Роль `remnanode` на этапе деплоя новой ноды:**
   * Регистрирует её в панели Remnawave через API.
   * Получает сгенерированный `secretKey`.
   * **Автоматически создает** директорию `host_vars/eu_node_3/`.
   * Записывает публичные ссылки в `vars.yml` и plaintext-секрет в `vault.yml`.
   * Вызывает локальную утилиту `ansible-vault` для шифрования `vault.yml` на лету с использованием `.vault-pass`. Секрет сохраняется в защищенном виде и готов к коммиту в Git!

---

## 🔐 Работа с Ansible Vault вручную

Если вам нужно вручную зашифровать/расшифровать файлы или изменить пароль:
```bash
# Зашифровать файл
ansible-vault encrypt путь/к/файлу.yml

# Расшифровать файл (в plain-text)
ansible-vault decrypt путь/к/файлу.yml

# Просмотреть зашифрованный файл без изменения
ansible-vault view путь/к/файлу.yml

# Сменить пароль шифрования для всех файлов
ansible-vault rekey group_vars/all/vault.yml host_vars/*/vault.yml
```

---
**Автор:** Андрей (Andrwy)  
**Рефакторинг:** Antigravity (Май 2026)