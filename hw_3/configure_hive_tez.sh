
#!/usr/bin/env bash
set -euo pipefail

HIVE_HOME="/home/team/apache-hive-4.1.0-bin"
TEZ_HOME="/home/team/apache-tez-0.10.5-bin"
HADOOP_HOME="/home/team/hadoop-3.5.0"

test "$(hostname -s)" = "team-14-en"
test -d "$TEZ_HOME/lib"
test -f "$TEZ_HOME/conf/tez-site.xml"
test -f "$HIVE_HOME/conf/hive-site.xml"

echo "Настраиваем Tez для HiveServer2"

# Создаём конфигурацию в каталоге, используемом Hive.
cp "$TEZ_HOME/conf/tez-site.xml" \
   "$HIVE_HOME/conf/tez-site.xml"

python3 - "$HIVE_HOME/conf/tez-site.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
tree = ET.parse(path)
root = tree.getroot()

settings = {
    "tez.lib.uris": "hdfs:///apps/tez/tez-0.10.5.tar.gz",
    "tez.lib.uris.classpath": "./tez/*:./tez/lib/*",
    "tez.use.cluster.hadoop-libs": "true",
}

for key, value in settings.items():
    prop = next(
        (p for p in root.findall("property")
         if p.findtext("name") == key),
        None
    )
    if prop is None:
        prop = ET.SubElement(root, "property")
        ET.SubElement(prop, "name").text = key
    val = prop.find("value")
    if val is None:
        val = ET.SubElement(prop, "value")
    val.text = value

tree.write(path, encoding="utf-8",
           xml_declaration=True)
print("Tez configuration OK")
PY

echo "Проверяем необходимые библиотеки"

find "$TEZ_HOME" -name 'tez-mapreduce-*.jar' \
  -print -quit | grep -q .

echo "Конфигурация подготовлена"
echo "HiveServer2 требуется перезапуск с TEZ_CONF_DIR"
