#!/usr/bin/env bash
set -euo pipefail

HADOOP_HOME="/home/team/hadoop-3.5.0"
HIVE_HOME="/home/team/apache-hive-4.1.0-bin"

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HDFS_DATA_DIR="/user/team/hw3/raw_transactions"

echo "=== Проверяем необходимые программы ==="

if [[ ! -x "$HADOOP_HOME/bin/hdfs" ]]; then
    echo "Ошибка: Hadoop не найден"
    exit 1
fi

if [[ ! -x "$HIVE_HOME/bin/beeline" ]]; then
    echo "Ошибка: Hive Beeline не найден"
    exit 1
fi

echo "=== Проверяем файлы ==="

for file in transactions.csv create_table.sql load_data.sql; do
    if [[ ! -f "$WORK_DIR/$file" ]]; then
        echo "Ошибка: отсутствует $file"
        exit 1
    fi
done

echo "=== Создаем каталог в HDFS ==="

"$HADOOP_HOME/bin/hdfs" dfs -mkdir -p "$HDFS_DATA_DIR"

echo "=== Загружаем CSV в HDFS ==="

"$HADOOP_HOME/bin/hdfs" dfs \
    -put -f "$WORK_DIR/transactions.csv" \
    "$HDFS_DATA_DIR/transactions.csv"

echo "=== Создаём таблицы Hive ==="

"$HIVE_HOME/bin/beeline" \
    -u "jdbc:hive2://localhost:10000/default" \
    -f "$WORK_DIR/create_table.sql"

echo "=== Загружаем данные в Hive ==="

"$HIVE_HOME/bin/beeline" \
    -u "jdbc:hive2://localhost:10000/default" \
    -f "$WORK_DIR/load_data.sql"

echo "=== Загрузка завершена ==="