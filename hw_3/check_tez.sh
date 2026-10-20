#!/usr/bin/env bash
set -euo pipefail

echo "=== Проверка Tez на сервере ==="
hostname

echo "=== Каталоги Tez ==="
for dir in /home/team/tez /home/team/apache-tez* /opt/tez /usr/local/tez; do
    if [[ -d "$dir" ]]; then
        echo "Найден: $dir"
    fi
done

echo "=== Переменные окружения ==="
printenv | grep -Ei 'TEZ_HOME|TEZ_CONF_DIR|HIVE_HOME' || true

echo "=== Настройки Hadoop ==="
find /home/team/hadoop-3.5.0/etc/hadoop \
    -maxdepth 1 -type f \
    -name '*tez*' -print 2>/dev/null

echo "=== Файлы Tez ==="
find /home/team -maxdepth 3 \
    \( -name 'tez-api*.jar' -o -name 'tez-site.xml' \) \
    -print 2>/dev/null
