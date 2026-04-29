

# 🚀 Remnawave + Xray Bridge Deployment

Этот проект автоматизирует развертывание VPN-инфраструктуры "Матрёшка": европейские ноды Remnawave маскируются через российский сервер в Яндекс.Облаке.

## 📋 Требования (на твоем ПК / новой машине)
1. **Python 3** и **Ansible** (`sudo apt install ansible`)
2. **SSH-доступ** по ключам ко всем серверам.
3. Установленная коллекция (нужна для некоторых модулей):
   ```bash
   ansible-galaxy collection install community.docker
   ```

## 📂 Структура проекта
* `inventory.ini` — список твоих серверов и их настроек.
* `deploy.yml` — главный сценарий (плейбук).
* `group_vars/all.yml` — общие настройки API твоей панели.
* `templates/` — папка с шаблонами конфигов (Xray, Docker, Telemt).

---

## 🛠 Настройка перед запуском

### 1. Отредактируй `inventory.ini`
Укажи свои IP и секреты нод (секрет берется в админке Remnawave):
```ini
[yandex]
yandex_node ansible_host=IP_ЯНДЕКСА ansible_user=andrwy

[eu_nodes]
bulgaria_main ansible_host=femboyhooters.kawaiinekos.cfd ansible_user=root node_port=3743 node_secret="ВАШ_СЕКРЕТ" bridge_sni=www.microsoft.com
eu_node_2     ansible_host=caffeinated.kawaiinekos.cfd ansible_user=root node_port=1488 node_secret="ВАШ_СЕКРЕТ" bridge_sni=drive.google.com
```

### 2. Настрой `group_vars/all.yml`
Впиши токен и ID профиля из своей панели:
```yaml
remnawave_domain: "nekodera.kawaiinekos.cfd"
remnawave_api_token: "ВАШ_API_TOKEN_ИЗ_АДМИНКИ"
remnawave_profile_uuid: "7b819d85-3004-480f-99a7-43337e47cbba"
remnawave_inbounds:
  - "UUID_1"
  - "UUID_2"
```

---

## 🚀 Запуск деплоя

Чтобы запустить настройку всей сети с нуля на новой машине, выполни:

```bash
ansible-playbook deploy.yml -i inventory.ini
```

### Что сделает скрипт:
1. **На серверах в Европе:**
   * Установит Docker.
   * Проверит/зарегистрирует ноду в панели Remnawave и запустит её.
   * Сгенерирует уникальные ключи Xray и запустит `bridge-receiver`.
   * Настроит и запустит Telegram-прокси `telemt`.
2. **На сервере Яндекса:**
   * Настроит `bridge-sender` (подключится ко всем EU-нодам).
   * Автоматически пропишет новые бекенды в HAProxy (Hiddify).
   * Исправит конфиг Hiddify (добавит переносы строк) и применит настройки.

---

## ⚠️ Решение частых ошибок
* **"node_secret is undefined"**: Проверь, что в `inventory.ini` для каждой ноды прописан `node_secret`.
* **"Missing LF on last line"**: Скрипт фиксит это автоматически, но если HAProxy не стартует, проверь `haproxy.cfg.j2` на наличие пустых строк в конце.
* **"sudo: a password is required"**: Убедись, что на серверах у пользователя настроен беспарольный sudo, либо запускай с флагом `-K` (но лучше настроить SSH-ключи).

---

## ➕ Добавление новой ноды (через бот или вручную)

`scripts/add_node.sh` — helper, который вызывается Telegram-ботом
([bot_remna](https://github.com/L1ttleWizard/bot_remna)) для добавления новых
EU-нод. Можно запускать и руками с master-ноды.

```bash
# С master-ноды (Болгарии), где лежит этот клон репо:
./scripts/add_node.sh \
    --name eu_node_3 \
    --address node3.example.com \
    --ssh-port 22 \
    --node-port 3743 \
    --bridge-sni www.microsoft.com \
    --country NL
```

Что делает скрипт:
1. Валидирует аргументы.
2. Дописывает запись в секцию `[eu_nodes]` файла `inventory.ini` (если её ещё нет).
3. (опционально) Если задан `SSHPASS_INITIAL` — копирует pubkey master на новую
   ноду через `sshpass`+`ssh-copy-id`. Пример:
   `SSHPASS_INITIAL='пароль_root' ./scripts/add_node.sh ...`
4. Делает `ansible -m ping` чтобы убедиться в доступности.
5. Запускает `ansible-playbook deploy.yml -l <name>`.

Бот вызывает скрипт по SSH с master, передавая все аргументы; стримит вывод в
Telegram-сообщение.

---

## 🔐 Секреты и `ansible-vault`

⚠️ **Сейчас в репозитории секреты лежат в открытом виде** —
`group_vars/all.yml` (Remnawave API token) и `inventory.ini` (node_secret для
каждой ноды). Если репо когда-либо был публичным или попал к третьим лицам:

1. Зайди в админку Remnawave → API tokens → отозви старый, создай новый.
2. Удали ноды из панели и пересоздай — у новых будет новый `node_secret`.
3. Замени значения в `group_vars/all.yml` и `inventory.ini` на новые.

После ротации — рекомендую перенести секреты в `ansible-vault`:

```bash
# Создать vault-файл с секретами
ansible-vault create group_vars/all/vault.yml
# Внутри:
#   vault_remnawave_api_token: "..."
#   vault_node_secrets:
#     bulgaria_main: "..."
#     eu_node_2: "..."

# Поправить group_vars/all.yml — заменить токен ссылкой на vault-переменную:
#   remnawave_api_token: "{{ vault_remnawave_api_token }}"

# Запускать playbook с паролем vault:
ansible-playbook deploy.yml -i inventory.ini --ask-vault-pass
# или с файлом-паролем:
ansible-playbook deploy.yml -i inventory.ini --vault-password-file ~/.vault_pass
```

См. [официальную документацию ansible-vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html).

---
**Автор:** Андрей (Andrwy)
**Дата:** Апрель 2026