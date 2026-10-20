#!/usr/bin/env bash
set -euo pipefail

HIVE_VERSION="4.1.0"
TEZ_VERSION="0.10.5"

echo "=== Проверяем окружение ==="

test "$(hostname -s)" = "team-14-en"
test "$(whoami)" = "team"
test -x "$HOME/hadoop-3.5.0/bin/hadoop"

echo "=== Подготавливаем каталог ==="

mkdir -p "$HOME/hw3-downloads"
cd "$HOME/hw3-downloads"

echo "=== Скачиваем Apache Hive ==="

curl -fL --retry 3 \
  -o "apache-hive-${HIVE_VERSION}-bin.tar.gz" \
  "https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz"

echo "=== Скачиваем Apache Tez ==="

curl -fL --retry 3 \
  -o "apache-tez-${TEZ_VERSION}-bin.tar.gz" \
  "https://archive.apache.org/dist/tez/${TEZ_VERSION}/apache-tez-${TEZ_VERSION}-bin.tar.gz"

echo "=== Проверяем архивы ==="

tar -tzf "apache-hive-${HIVE_VERSION}-bin.tar.gz" >/dev/null
tar -tzf "apache-tez-${TEZ_VERSION}-bin.tar.gz" >/dev/null

echo "Архивы скачаны и успешно проверены"
