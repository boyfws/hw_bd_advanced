#!/usr/bin/env bash
set -euo pipefail

HIVE_VERSION="4.1.0"
TEZ_VERSION="0.10.5"

HADOOP_HOME="$HOME/hadoop-3.5.0"
HIVE_HOME="$HOME/apache-hive-${HIVE_VERSION}-bin"
TEZ_HOME="$HOME/apache-tez-${TEZ_VERSION}-bin"

REMOTE_HOST="team-14-00"
SSH_KEY="$HOME/.ssh/team_internal"
PASSWORD_FILE="$HOME/.hive_db_password"

echo "Проверка окружения"

test "$(hostname -s)" = "team-14-en"
test "$(whoami)" = "team"
test -x "$HADOOP_HOME/bin/hadoop"
test -x "$HIVE_HOME/bin/hive"
test -x "$HIVE_HOME/bin/beeline"
test -d "$TEZ_HOME"
test -f "$PASSWORD_FILE"
test -s "$PASSWORD_FILE"
test -f "$SSH_KEY"

echo "Проверка HDFS"

"$HADOOP_HOME/bin/hdfs" dfs -ls / >/dev/null

echo "Проверка удалённого узла"

ssh -i "$SSH_KEY" \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  "team@$REMOTE_HOST" 'bash -se' <<'REMOTE'
set -euo pipefail

test "$(hostname -s)" = "team-14-00"
test "$(whoami)" = "team"

echo "Проверяем Hadoop"
jps | grep -E '[[:space:]]DataNode$'
jps | grep -E '[[:space:]]NodeManager$'

echo "Проверяем PostgreSQL"
sudo -n -u postgres psql -Atqc 'SELECT 1;'
echo "Проверяем журналирование SQL"
sudo -n -u postgres psql -Atqc 'SHOW log_statement;'
sudo -n -u postgres psql -Atqc 'SHOW log_min_error_statement;'

echo "Проверяем базу Hive"
sudo -n -u postgres psql -Atqc \
  "SELECT datname FROM pg_database WHERE datname='hive_metastore';" \
  | grep -qx hive_metastore

echo "Проверяем пользователя Hive"
sudo -n -u postgres psql -Atqc \
  "SELECT rolname FROM pg_roles WHERE rolname='hive';" \
  | grep -qx hive

echo "Проверяем свободное место"
df -h /

echo "Удалённый узел готов"
REMOTE
if [[ "${1:-}" == "--check-only" ]]; then
    echo "Проверки завершены. Изменения не выполнялись."
    exit 0
fi
echo "Настройка доступа Hive к PostgreSQL"

python3 - "$PASSWORD_FILE" <<'PY' | \
ssh -i "$SSH_KEY" \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  "team@$REMOTE_HOST" \
    'sudo -n -u postgres psql -X -q -v ON_ERROR_STOP=1'
import pathlib
import sys

password = pathlib.Path(sys.argv[1]).read_text()

if not password or len(password) > 128:
    raise SystemExit("Некорректный пароль Hive")

escaped = password.replace("'", "''")

print("SET log_min_error_statement = PANIC;")
print("ALTER ROLE hive WITH LOGIN PASSWORD '" + escaped + "';")
PY

echo "Проверка роли Hive"

ssh -i "$SSH_KEY" \
  -o BatchMode=yes \
  "team@$REMOTE_HOST" \
  "sudo -n -u postgres psql -Atqc \"SELECT rolcanlogin FROM pg_roles WHERE rolname = 'hive';\"" \
  | grep -qx t

echo "Доступ пользователя hive настроен"


echo "Проверка возможности установки Hive"

test -f "$HOME/hw3-downloads/apache-hive-${HIVE_VERSION}-bin.tar.gz"
test -f "$HOME/hw3-downloads/apache-tez-${TEZ_VERSION}-bin.tar.gz"

echo "Результат"
echo "PostgreSQL, Hive, Tez и Hadoop обнаружены."
echo "Предварительные проверки завершены успешно."
echo "Службы Hadoop не изменялись."




echo "Подготовка Hive Metastore"

METASTORE_HOST="team-14-00"

ssh -i "$SSH_KEY" -o BatchMode=yes \
  "team@$METASTORE_HOST" \
  'mkdir -p "$HOME/hw3-downloads"'

scp -i "$SSH_KEY" -o BatchMode=yes \
  "$HOME/hw3-downloads/apache-hive-${HIVE_VERSION}-bin.tar.gz" \
  "team@$METASTORE_HOST:/home/team/hw3-downloads/"

ssh -i "$SSH_KEY" -o BatchMode=yes \
  "team@$METASTORE_HOST" 'bash -se' <<'METASTORE'
set -euo pipefail

HIVE_HOME="$HOME/apache-hive-4.1.0-bin"
ARCHIVE="$HOME/hw3-downloads/apache-hive-4.1.0-bin.tar.gz"

test "$(hostname -s)" = "team-14-00"
test -f "$ARCHIVE"

if [[ ! -d "$HIVE_HOME" ]]; then
    echo "Распаковываем Hive"
    tar -xzf "$ARCHIVE" -C "$HOME"
fi

test -x "$HIVE_HOME/bin/hive"
test -x "$HIVE_HOME/bin/schematool"

echo "Устанавливаем PostgreSQL JDBC"
if ! dpkg-query -W -f='${Status}' \
    libpostgresql-jdbc-java 2>/dev/null |
    grep -q 'install ok installed'; then
    sudo -n env DEBIAN_FRONTEND=noninteractive \
      apt-get install -y --no-install-recommends \
      libpostgresql-jdbc-java
fi

test -f /usr/share/java/postgresql.jar

echo "Подключаем JDBC-драйвер к Hive"
ln -sfn /usr/share/java/postgresql.jar \
  "$HIVE_HOME/lib/postgresql.jar"

echo "Проверяем подготовку"
test -x "$HIVE_HOME/bin/schematool"
test -e "$HIVE_HOME/lib/postgresql.jar"

echo "Hive Metastore: файлы и JDBC подготовлены"
METASTORE


echo "Проверка PostgreSQL для Hive Metastore"

ssh -i "$SSH_KEY" \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  "team@$REMOTE_HOST" 'bash -se' <<'METASTORE_CHECK'
set -euo pipefail

HIVE_HOME="$HOME/apache-hive-4.1.0-bin"

test "$(hostname -s)" = "team-14-00"
test -x "$HIVE_HOME/bin/schematool"
test -e "$HIVE_HOME/lib/postgresql.jar"

sudo -n -u postgres psql -Atqc \
  "SELECT rolcanlogin FROM pg_roles WHERE rolname='hive';" \
  | grep -qx t

sudo -n -u postgres psql -Atqc \
  "SELECT datname FROM pg_database WHERE datname='hive_metastore';" \
  | grep -qx hive_metastore

echo "Hive Metastore готов к настройке подключения"
METASTORE_CHECK



echo "Настраиваем Hive Metastore"

# Передаём пароль на сервер Metastore без вывода в журнал
ssh -i "$SSH_KEY" -o BatchMode=yes \
  "team@$REMOTE_HOST" \
  'umask 077; cat > "$HOME/.hw3_metastore_password"' \
  < "$PASSWORD_FILE"

ssh -i "$SSH_KEY" \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  "team@$REMOTE_HOST" 'bash -se' <<'METASTORE_SETUP'
set -euo pipefail

test "$(hostname -s)" = "team-14-00"

HIVE_HOME="$HOME/apache-hive-4.1.0-bin"
HADOOP_HOME="$HOME/hadoop-3.5.0"
PASSWORD_FILE="$HOME/.hw3_metastore_password"
CONFIG_FILE="$HIVE_HOME/conf/hive-site.xml"
LOG_FILE="$HOME/hw3-metastore.log"

export HIVE_HOME HADOOP_HOME
export PATH="$HIVE_HOME/bin:$HADOOP_HOME/bin:$PATH"

# Удаляем временную копию пароля после настройки.
trap 'rm -f "$PASSWORD_FILE"' EXIT

test -x "$HIVE_HOME/bin/schematool"
test -x "$HADOOP_HOME/bin/hadoop"
test -e "$HIVE_HOME/lib/postgresql.jar"
test -s "$PASSWORD_FILE"

echo "Создаём конфигурацию Metastore"

python3 - "$CONFIG_FILE" "$PASSWORD_FILE" <<'PY'
import sys
import pathlib
import xml.etree.ElementTree as ET

config_path = pathlib.Path(sys.argv[1])
password_path = pathlib.Path(sys.argv[2])
password = password_path.read_text()

if not password or len(password) > 128:
    raise SystemExit("Invalid database password")

properties = {
    "javax.jdo.option.ConnectionURL":
        "jdbc:postgresql://127.0.0.1:5432/hive_metastore",
    "javax.jdo.option.ConnectionDriverName":
        "org.postgresql.Driver",
    "javax.jdo.option.ConnectionUserName": "hive",
    "javax.jdo.option.ConnectionPassword": password,
    "datanucleus.connectionPool.maxPoolSize": "5",
    "hive.metastore.warehouse.dir":
        "/user/hive/warehouse",
    "hive.metastore.schema.verification": "true",
}

root = ET.Element("configuration")

for name, value in properties.items():
    item = ET.SubElement(root, "property")
    ET.SubElement(item, "name").text = name
    ET.SubElement(item, "value").text = value

tree = ET.ElementTree(root)
tree.write(
    config_path,
    encoding="utf-8",
    xml_declaration=True
)
config_path.chmod(0o600)

print("Metastore configuration created")
PY

echo "Проверяем состояние Metastore"

if ss -ltnp | grep -Eq ':9083[[:space:]]'; then
    echo "Metastore уже работает — повторная проверка PostgreSQL не требуется"
else
    echo "Metastore не запущен — проверяем PostgreSQL"

    PGPASSWORD="$(cat "$PASSWORD_FILE")" \
      psql -h 127.0.0.1 -U hive \
      -d hive_metastore -Atqc 'SELECT 1' \
      | grep -qx 1
fi

echo "Проверяем необходимость инициализации схемы"

if ss -ltnp | grep -Eq ':9083[[:space:]]'; then
    echo "Metastore уже работает — схему повторно не проверяем"
else
    echo "Metastore не запущен — проверяем схему"

    "$HIVE_HOME/bin/schematool" \
        -dbType postgres -info
fi

echo "Запускаем Metastore"

if ss -ltn | grep -Eq ':9083[[:space:]]'; then
    echo "Metastore уже слушает порт 9083"
else
    export HADOOP_CLIENT_OPTS="-Xmx768m"

    nohup "$HIVE_HOME/bin/hive" --service metastore \
        > "$LOG_FILE" 2>&1 < /dev/null &

    echo "Ожидаем запуск Metastore"

    READY=0
    for attempt in $(seq 1 30); do
        if ss -ltn | grep -Eq ':9083[[:space:]]'; then
            READY=1
            break
        fi
        sleep 2
    done

    if [[ "$READY" -ne 1 ]]; then
        echo "Metastore не открыл порт 9083"
        exit 1
    fi
fi


METASTORE_SETUP

echo "Запуск HiveServer2"

# Проверяем, что Metastore доступен с edge-ноды
if ! timeout 5 bash -c \
  'echo > /dev/tcp/team-14-00/9083' 2>/dev/null; then
    echo "ОШИБКА: Metastore недоступен с edge-ноды"
    exit 1
fi

export HIVE_HOME="$HOME/apache-hive-4.1.0-bin"
export HADOOP_HOME="$HOME/hadoop-3.5.0"
export PATH="$HIVE_HOME/bin:$HADOOP_HOME/bin:$PATH"

# Создаем отдельную конфигурацию HiveServer2
mkdir -p "$HIVE_HOME/conf"

python3 - "$HIVE_HOME/conf/hive-site.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

properties = {
    "hive.metastore.uris": "thrift://team-14-00:9083",
    "hive.server2.thrift.port": "10000",
    "hive.server2.thrift.bind.host": "127.0.0.1",
    "hive.server2.authentication": "NONE",
    "hive.server2.enable.doAs": "false",
    "hive.execution.engine": "tez",
    "hive.metastore.warehouse.dir": "/user/hive/warehouse",
}

root = ET.Element("configuration")
for key, value in properties.items():
    prop = ET.SubElement(root, "property")
    ET.SubElement(prop, "name").text = key
    ET.SubElement(prop, "value").text = value

path = Path(sys.argv[1])
ET.ElementTree(root).write(
    path, encoding="utf-8", xml_declaration=True
)
print("Конфигурация HiveServer2 создана")
PY

# Не запускаем второй экземпляр на занятом порту
if ss -ltn | grep -Eq ':10000[[:space:]]'; then
    echo "Порт 10000 уже занят; второй сервер не запускаем"
    exit 1
fi

echo "Запускаем HiveServer2"

nohup "$HIVE_HOME/bin/hiveserver2" \
  > "$HOME/hw3-hiveserver2.log" 2>&1 < /dev/null &

HS2_PID=$!
echo "PID HiveServer2: $HS2_PID"

echo "Ожидаем порт 10000"

READY=0
for attempt in $(seq 1 60); do
    if ss -ltn | grep -Eq ':10000[[:space:]]'; then
        READY=1
        break
    fi
    if ! kill -0 "$HS2_PID" 2>/dev/null; then
        echo "Процесс HiveServer2 завершился"
        break
    fi
    sleep 2
done

if [[ "$READY" -ne 1 ]]; then
    echo "HiveServer2 не запустился"
    echo "Журнал: $HOME/hw3-hiveserver2.log"
    exit 1
fi

echo "HiveServer2 слушает порт 10000"
