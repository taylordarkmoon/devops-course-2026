# Конфигурация виртуальной машины devops-vm

Обозначения: **[Хост]** — команды на хостовой системе (Windows, PowerShell), **[VM]** — команды на сервере.

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Средство виртуализации | Oracle VirtualBox 7.2.22 |
| Имя машины / имя узла | `devops-vm` (FQDN `devops-vm.devops.local`) |
| Тип гостевой ОС | Linux / Ubuntu (64-bit) |
| ОС | Ubuntu Server 24.04.5 LTS (образ `ubuntu-24.04.5-live-server-amd64.iso`) |
| Оперативная память | 2048 МБ |
| Процессор | 2 ядра |
| Диск | 25 ГБ, VDI, динамически расширяемый; разметка «Use an entire disk» без LVM |
| Установка | тип Ubuntu Server (не minimized), OpenSSH server установлен, Featured snaps не выбраны |

Примечание: на хосте Windows для работы VirtualBox с аппаратной виртуализацией (VT-x) отключены «Целостность памяти», запуск гипервизора (`bcdedit /set hypervisorlaunchtype off`) и VBS (`EnableVirtualizationBasedSecurity=0`).

## 2. Сетевые интерфейсы

| Адаптер VirtualBox | Интерфейс в ВМ | Адрес | Назначение |
|---|---|---|---|
| 1 — NAT | `enp0s3` | `10.0.2.15/24` (DHCP) | Доступ в Интернет, репозитории пакетов; вход по SSH через проброс порта |
| 2 — Host-only (`VirtualBox Host-Only Ethernet Adapter`, хост `192.168.56.1`) | `enp0s8` | `192.168.56.101/24` (DHCP) | Прямой доступ с хоста: имя `devops.local`, веб-сервер (ПР № 6) |

Имя `devops.local` задано на хосте в `C:\Windows\System32\drivers\etc\hosts`:

```
192.168.56.101    devops.local
```

## 3. Правило проброса портов

| Имя | Протокол | Адрес хоста | Порт хоста | Адрес гостя | Порт гостя |
|---|---|---|---|---|---|
| `ssh` | TCP | `127.0.0.1` | `2222` | — | `2222` (до задания 2 был `22`) |

## 4. Учётные записи

| Имя | Группы | Способ аутентификации |
|---|---|---|
| `student` | student, adm, cdrom, **sudo**, dip, plugdev, lxd | Пароль; только локальная консоль (по SSH вход запрещён директивой `AllowUsers devops`) |
| `devops` | devops, **sudo**, users | Только по ключу ED25519 (`~/.ssh/devops_vm` на хосте); пароль используется для `sudo` |

Ключ клиента — отдельная пара для сервера (не ключ из ПР № 1):

```
ssh-keygen -t ed25519 -C "devops-vm-key" -f $env:USERPROFILE\.ssh\devops_vm      # passphrase пустая
```

Права на сервере: `~/.ssh` — `700`, `~/.ssh/authorized_keys` — `600`.

Файл `~/.ssh/config` на хосте:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Отпечаток ключа сервера (ED25519): `SHA256:nJHggd+dd5JYU3rBO3ArowHTsrewwIEccTDRjFkibII`.

## 5. Служба SSH

- Порт: **2222**.
- Основной файл `/etc/ssh/sshd_config` не изменялся; эталонная копия — `/etc/ssh/sshd_config.backup`.
- Изменённые директивы — в файле `/etc/ssh/sshd_config.d/99-hardening.conf` (владелец root, права 644):

| Директива | Значение |
|---|---|
| `Port` | `2222` |
| `PermitRootLogin` | `no` |
| `PasswordAuthentication` | `no` |
| `PubkeyAuthentication` | `yes` |
| `PermitEmptyPasswords` | `no` |
| `MaxAuthTries` | `3` |
| `LoginGraceTime` | `30` |
| `AllowUsers` | `devops` |
| `X11Forwarding` | `no` |
| `ClientAliveInterval` | `300` |
| `ClientAliveCountMax` | `2` |

- В `/etc/ssh/sshd_config.d/50-cloud-init.conf` строка `PasswordAuthentication yes` закомментирована: файлы читаются по алфавиту, действует первое значение, поэтому `50-` перекрывал `99-`.
- Активация по сокету отключена: `ssh.socket` — disabled, `ssh.service` — enabled (иначе порт задавался бы юнитом сокета, а не директивой `Port`).
- Действующие значения проверяются командой `sudo sshd -T`, а не чтением файлов.

## 6. Правила межсетевого экрана

- Политики по умолчанию: `deny (incoming)`, `allow (outgoing)`, `disabled (routed)`.
- Журналирование: `medium` (записи `[UFW BLOCK]` — в журнале ядра, `sudo journalctl -k`).

| Порт | Действие | Комментарий |
|---|---|---|
| `2222/tcp` | `LIMIT` | SSH rate-limited (блокировка источника при 6 и более соединениях за 30 с) |
| `80/tcp` | `ALLOW` | HTTP (ПР № 6) |
| `443/tcp` | `ALLOW` | HTTPS (ПР № 6) |

Правила действуют для IPv4 и IPv6.

## 7. Снимки состояния

| Имя | Момент создания (МСК) | Состояние |
|---|---|---|
| `01-clean-install` | 28.10.2026 01:11 | Чистая установка, `apt upgrade`, ключи хоста сгенерированы (`ssh-keygen -A`), SSH на порту 22 |
| `02-keys-configured` | 28.10.2026 01:52 | Пользователь `devops`, вход по ключу, `~/.ssh/config` |
| `03-ssh-hardened` | 28.10.2026 02:17 | Усиление SSH, порт 2222, проброс 2222 → 2222 |

## 8. Восстановление конфигурации со снимка 01-clean-install

Порядок операций важен: действующая SSH-сессия не закрывается, пока новая конфигурация не проверена во втором окне; разрешающее правило UFW создаётся до включения экрана.

**1. [Хост]** Восстановить снимок `01-clean-install`, запустить ВМ. Проброс порта после отката указывает на гостевой порт 22.

**2. [Хост]** Вход и создание пользователя:

```
ssh student@127.0.0.1 -p 2222
```

```
sudo adduser devops
sudo usermod -aG sudo devops
exit
```

**3. [Хост]** Ключ (если файла `~/.ssh/devops_vm` ещё нет — создать командой из раздела 4) и копирование на сервер:

```
type $env:USERPROFILE\.ssh\devops_vm.pub | ssh devops@127.0.0.1 -p 2222 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
ssh -i $env:USERPROFILE\.ssh\devops_vm -p 2222 devops@127.0.0.1
```

**4. [VM]** Усиление SSH (в открытой сессии, каждая команда — одной строкой):

```
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
printf '%s\n' 'Port 2222' '' 'PermitRootLogin no' 'PasswordAuthentication no' 'PubkeyAuthentication yes' 'PermitEmptyPasswords no' 'MaxAuthTries 3' 'LoginGraceTime 30' '' 'AllowUsers devops' '' 'X11Forwarding no' 'ClientAliveInterval 300' 'ClientAliveCountMax 2' | sudo tee /etc/ssh/sshd_config.d/99-hardening.conf
sudo sed -i 's/^PasswordAuthentication yes/#PasswordAuthentication yes/' /etc/ssh/sshd_config.d/50-cloud-init.conf
sudo sshd -t && sudo sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)"
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd
```

**5. [Хост]** Перевести проброс на гостевой порт 2222 (или в окне «Настроить → Сеть → Адаптер 1 → Проброс портов»):

```
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" controlvm devops-vm natpf1 delete ssh
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" controlvm devops-vm natpf1 "ssh,tcp,127.0.0.1,2222,,2222"
```

Проверить во **втором** окне: `ssh devops` — успех; `ssh -p 2222 root@127.0.0.1` — отказ.

**6. [VM]** Межсетевой экран:

```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw --force enable
sudo ufw logging medium
sudo ufw status verbose
```

**7. [VM]** Полное имя узла:

```
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f
```

**8.** Проверка: `scripts/audit.sh` завершается с кодом 0.
