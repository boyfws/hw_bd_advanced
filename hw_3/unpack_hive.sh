#!/usr/bin/env bash
set -euo pipefail

HIVE_VERSION="4.1.0"
TEZ_VERSION="0.10.5"

DOWNLOAD_DIR="$HOME/hw3-downloads"
HIVE_DIR="$HOME/apache-hive-${HIVE_VERSION}-bin"
TEZ_DIR="$HOME/apache-tez-${TEZ_VERSION}-bin"

echo "Проверяем сервер"
test "$(hostname -s)" = "team-14-en"
test "$(whoami)" = "team"

echo "Проверяем архивы"
test -f "$DOWNLOAD_DIR/apache-hive-${HIVE_VERSION}-bin.tar.gz"
test -f "$DOWNLOAD_DIR/apache-tez-${TEZ_VERSION}-bin.tar.gz"

echo "Распаковываем Hive"
if [[ ! -d "$HIVE_DIR" ]]; then
    tar -xzf "$DOWNLOAD_DIR/apache-hive-${HIVE_VERSION}-bin.tar.gz" -C "$HOME"
else
    echo "Hive уже распакован"
fi

echo "Распаковываем Tez"
if [[ ! -d "$TEZ_DIR" ]]; then
    tar -xzf "$DOWNLOAD_DIR/apache-tez-${TEZ_VERSION}-bin.tar.gz" -C "$HOME"
else
    echo "Tez уже распакован"
fi

echo "Проверяем результат"
test -x "$HIVE_DIR/bin/hive"
test -x "$HIVE_DIR/bin/beeline"
test -d "$TEZ_DIR"

echo "Hive и Tez распакованы"
