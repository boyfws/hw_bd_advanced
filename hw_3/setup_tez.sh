
#!/usr/bin/env bash
set -euo pipefail

HADOOP_HOME="/home/team/hadoop-3.5.0"
TEZ_HOME="/home/team/apache-tez-0.10.5-bin"
TEZ_ARCHIVE="/home/team/hw3-downloads/apache-tez-0.10.5-bin.tar.gz"

HDFS_TEZ_DIR="/apps/tez"
HDFS_TEZ_ARCHIVE="$HDFS_TEZ_DIR/tez-0.10.5.tar.gz"

echo "Проверяем Tez и Hadoop"

test "$(hostname -s)" = "team-14-en"
test -x "$HADOOP_HOME/bin/hdfs"
test -d "$TEZ_HOME"
test -s "$TEZ_ARCHIVE"

echo "Проверяем HDFS"

"$HADOOP_HOME/bin/hdfs" dfs -ls / >/dev/null

echo "Подготавливаем каталог Tez в HDFS"

"$HADOOP_HOME/bin/hdfs" dfs -mkdir -p "$HDFS_TEZ_DIR"

if "$HADOOP_HOME/bin/hdfs" dfs -test -e "$HDFS_TEZ_ARCHIVE"; then
    echo "Архив Tez уже существует в HDFS"
else
    echo "Загружаем архив Tez"
    "$HADOOP_HOME/bin/hdfs" dfs \
      -put "$TEZ_ARCHIVE" "$HDFS_TEZ_ARCHIVE"
fi

echo "Создаем конфигурацию Tez"

mkdir -p "$TEZ_HOME/conf"

cat > "$TEZ_HOME/conf/tez-site.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>tez.lib.uris</name>
    <value>hdfs:///apps/tez/tez-0.10.5.tar.gz</value>
  </property>
  <property>
    <name>tez.use.cluster.hadoop-libs</name>
    <value>true</value>
  </property>
</configuration>
XML

echo "Проверяем результат"

"$HADOOP_HOME/bin/hdfs" dfs -ls "$HDFS_TEZ_ARCHIVE"

python3 - <<'PY'
import xml.etree.ElementTree as ET

ET.parse(
    "/home/team/apache-tez-0.10.5-bin/conf/tez-site.xml"
)
print("Конфигурация Tez корректна")
PY

echo "Подготовка Tez завершена"
