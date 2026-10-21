
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

echo "Проверка возможности установки Hive"

test -f "$HOME/hw3-downloads/apache-hive-${HIVE_VERSION}-bin.tar.gz"
test -f "$HOME/hw3-downloads/apache-tez-${TEZ_VERSION}-bin.tar.gz"

echo "Результат"
echo "PostgreSQL, Hive, Tez и Hadoop обнаружены."
echo "Предварительные проверки завершены успешно."
echo "Службы Hadoop не изменялись."
