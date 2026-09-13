#!/usr/bin/env bash

set -euo pipefail

USER_NAME="student"
USER_HOME="/home/${USER_NAME}"


ssh-keygen -A


mkdir -p "${USER_HOME}/.ssh"

chmod 700 "${USER_HOME}/.ssh"


if [ ! -f /run/keys/authorized_key.pub ]; then
    echo "ERROR: /run/keys/authorized_key.pub not found"
    exit 1
fi

cp /run/keys/authorized_key.pub \
   "${USER_HOME}/.ssh/authorized_keys"

chmod 600 "${USER_HOME}/.ssh/authorized_keys"


if [ -f /run/keys/cluster_key ]; then
    cp /run/keys/cluster_key \
       "${USER_HOME}/.ssh/id_ed25519"

    chmod 600 "${USER_HOME}/.ssh/id_ed25519"
fi


chown -R "${USER_NAME}:${USER_NAME}" \
    "${USER_HOME}/.ssh"


exec /usr/sbin/sshd -D -e