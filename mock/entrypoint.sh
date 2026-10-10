#!/usr/bin/env bash

set -euo pipefail

USER_NAME="team"
USER_HOME="/home/${USER_NAME}"
SSH_DIR="${USER_HOME}/.ssh"

# Генерация SSH host keys
ssh-keygen -A

# Создание директории SSH
mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"

# Публичный ключ для входящих подключений
if [ ! -s /run/keys/authorized_key.pub ]; then
    echo "ERROR: /run/keys/authorized_key.pub not found" >&2
    exit 1
fi

cp /run/keys/authorized_key.pub \
    "${SSH_DIR}/authorized_keys"

chmod 600 "${SSH_DIR}/authorized_keys"

# Приватный ключ для перехода с edge
# на внутренние узлы
if [ -f /run/keys/cluster_key ]; then
    cp /run/keys/cluster_key \
        "${SSH_DIR}/team_internal"

    chmod 600 "${SSH_DIR}/team_internal"
fi

# Владелец SSH-файлов
chown -R "${USER_NAME}:${USER_NAME}" "${SSH_DIR}"

# Запуск SSH-сервера
exec /usr/sbin/sshd -D -e