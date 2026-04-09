

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
**Автор:** Андрей (Andrwy)
**Дата:** Апрель 2026