# Автоматизированное развертывание кластера HDFS

В этой работе автоматически разворачивается кластер HDFS из четырёх узлов: NameNode, Secondary NameNode и трёх DataNode. Развертывание запускается вручную через GitHub Actions. Workflow отвечает за подключение к edge-ноде и передачу скрипта, [deploy.sh](./deploy.sh) выполняется уже на edge-ноде и настраивает кластер.

## Состав кластера

Рассмотрим каждый узел, его адрес и что на нем хостится:
1. `team-14-nn`, `10.14.0.11`, NameNode и Secondary NameNode
2. `team-14-en`, `10.14.0.10`, Edge-нода и DataNode
3. `team-14-00`, `10.14.0.12`, DataNode 
4. `team-14-01`, `10.14.0.13`, DataNode

Для файлов HDFS задан фактор репликации `3`. Hadoop установлен в `$HOME/hadoop-3.5.0`, данные, метаданные, временные файлы и логи располагаются в `$HOME/hdfs/`.

## Как устроено развертывание

Файл [`.github/workflows/deploy-hdfs.yml`](../.github/workflows/deploy-hdfs.yml) запускается вручную (`workflow_dispatch`) черзе GitHub Actions

Что он делает:

1. Получает нужную ветку репо.
2. Проверяет синтаксис `hw_1/deploy.sh` командой `bash -n`, то есть нет ли ошибок в скрипте.
3. Записывает GitHub Secrets в необходимые папки (`.ssh`) и проверяет, действительно ли ключ отвечает требованиям для подключения 
4. Копирует `hw_1/deploy.sh` на `team@171.22.72.225` и запускает там через `bash`.

Скрипт работает на edge-ноде от пользователя `team`. Для команд на edge-ноде он использует свою оболочку, для остальных узлов — SSH с ключом `$HOME/.ssh/team_internal`.

Скрипт выполняет следующие действия:

1. Проверяет, что запущен на `team-14-en` от пользователя `team`, и проверяет доступность всех узлов, архитектуру, ОС, ресурсы.

```bash
if [[ "$(hostname -s)" != "$EDGE_NODE" ]]; then
    echo "запускай скрипт на $EDGE_NODE" >&2
    exit 1
fi

if [[ "$(whoami)" != "team" ]]; then
    echo "запускай скрипт под пользователем team" >&2
    exit 1
fi

if [[ ! -r "$SSH_KEY" ]]; then
    echo "не нашли ключ $SSH_KEY" >&2
    exit 1
fi
```

2. Устанавливает java, `curl`, сертификаты, `tar` и `gzip`. Если hadoop 3.5.0 ещё не установлен, загружает архив и сверяет его по хэшу.

```bash
sudo -n apt-get update
sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    openjdk-17-jdk-headless curl ca-certificates tar gzip

curl -fL --retry 10 \
    "https://downloads.apache.org/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz" \
    -o "$archive"
printf '%s  %s\n' "$HADOOP_SHA512" "$archive" | sha512sum -c -
tar -xzf "$archive" -C "$temp_d"
mv "$temp_d/hadoop-$HADOOP_VERSION" "$HADOOP_HOME"
```

3. Создаёт каталоги hdfs и записывает `hadoop-env.sh`, `core-site.xml` и `hdfs-site.xml` на каждом узле. rpc и http namenode bind-host привязаны к `0.0.0.0`, так как до этого была ошибка, что namenode не слушал ipv4 самой машины, а только localhost. Адреса сервисов datanode задаются внутренним ipv4 каждого узла.

```bash
mkdir -p "$HDFS_DIR/name" "$HDFS_DIR/data" "$HDFS_DIR/checkpoint" \
    "$HDFS_DIR/tmp" "$HDFS_DIR/logs" "$HDFS_DIR/pids"

cat > "$HADOOP_HOME/etc/hadoop/hadoop-env.sh" <<'DOG'
        export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
        export HADOOP_LOG_DIR="$HDFS_DIR/logs"
        export HADOOP_PID_DIR="$HDFS_DIR/pids"
        export HADOOP_HEAPSIZE_MAX="512m"
DOG
```

```bash
cat > "$HADOOP_HOME/etc/hadoop/core-site.xml" <<'DOGGY'
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://$NAMENODE_IP:8020</value>
    </property>
    <property>
        <name>hadoop.tmp.dir</name>
        <value>$HDFS_DIR/tmp</value>
    </property>
</configuration>
DOGGY

cat > "$HADOOP_HOME/etc/hadoop/hdfs-site.xml" <<'DOGGIK'
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>3</value>
    </property>
    <property>
        <name>dfs.namenode.rpc-address</name>
        <value>$NAMENODE_IP:8020</value>
    </property>
    <property>
        <name>dfs.namenode.http-address</name>
        <value>$NAMENODE_IP:9870</value>
    </property>
    <property>
        <name>dfs.namenode.secondary.http-address</name>
        <value>$NAMENODE_IP:9868</value>
    </property>
    <property>
        <name>dfs.namenode.rpc-bind-host</name>
        <value>0.0.0.0</value>
    </property>
    <property>
        <name>dfs.namenode.http-bind-host</name>
        <value>0.0.0.0</value>
    </property>
    <property>
        <name>dfs.datanode.address</name>
        <value>$node_ip:9866</value>
    </property>
    <property>
        <name>dfs.datanode.http.address</name>
        <value>$node_ip:9864</value>
    </property>
    <property>
        <name>dfs.datanode.ipc.address</name>
        <value>$node_ip:9867</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>file://$HDFS_DIR/name</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>file://$HDFS_DIR/data</value>
    </property>
    <property>
        <name>dfs.namenode.checkpoint.dir</name>
        <value>file://$HDFS_DIR/checkpoint</value>
    </property>
    <property>
        <name>dfs.namenode.checkpoint.period</name>
        <value>60</value>
    </property>
</configuration>
DOGGIK
```

4. Форматирует namenode только при первом запуске, когда метаданные namenode ещё не созданы. Перед форматированием происходит проверочка, что каталоги namenode, datanode на всех узлах пусты, иначе дропает скрипт с ошибкой.

```bash
if [[ -f "$HDFS_DIR/name/current/VERSION" ]]; then
    echo "initialized"
else
    echo "new"
fi
```

```bash
for node in "${NODES[@]}"; do
    func_on_node "$node" <<'BYE'
            set -euo pipefail

            for dir in "$HOME/hdfs/name" "$HOME/hdfs/data" "$HOME/hdfs/checkpoint"; do
                entry="$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit)"

                if [[ -n "$entry" ]]; then
                    echo "namenode не инициализирован, но $dir непуст. что-то не так" >&2
                    exit 1
                fi
            done
BYE
done
```

```bash
"$HADOOP_HOME/bin/hdfs" namenode -format -nonInteractive
```

5. Перезапускает namenode и ждёт до пяти минут, пока он начнёт отвечать. Затем запускает три datanode и secondary_namenode.

```bash
daemons_restart() {
    local node="$1"
    local daemon="$2"

    echo "перезапуск $daemon на $node"
    func_on_node "$node" <<ENDIKI
        set -euo pipefail
        "$HADOOP_HOME/bin/hdfs" --daemon stop "$daemon"
        "$HADOOP_HOME/bin/hdfs" --daemon start "$daemon"
ENDIKI
}

daemons_restart "$NAMENODE" "namenode"

if ! timeout 300 bash -c '
    until "$1/bin/hdfs" dfsadmin -safemode get >/dev/null 2>&1; do
        echo "ждём ответа namenode"
        sleep 3
    done
' _ "$HADOOP_HOME"; then
    echo "namenode не стал доступен за 300 секунд. логи:" >&2
    func_on_node "$NAMENODE" <<'KONEC'
        tail -n 80 "$HOME"/hdfs/logs/*-namenode-*.log
KONEC
    exit 1
fi
```

6. Проверяет, что hdfs видит три работающих и ни одного неработающего datanode, ждёт выхода из safe mode и проверяет http-ответ secondary_namenode.

```bash
for i in {1..10}; do
    if result="$(timeout 20 "$HADOOP_HOME/bin/hdfs" dfsadmin -report -live -dead)" &&
        [[ "$result" == *"Live datanodes (3):"* &&
           "$result" == *"Dead datanodes (0):"* ]]; then
        assert_ok=true
        break
    fi
    echo "ждем подтверждения жизнеспособности всех 3 датанод, попытка $i"
    sleep 5
done

timeout 300 "$HADOOP_HOME/bin/hdfs" dfsadmin -safemode wait
```

```bash
curl -fsS --max-time 60 -o /dev/null http://team-14-nn:9868/
```

## Настройка GitHub Actions

В репо гитхаба также располагаются secrets:

1. `SSH_PRIVATE`: приватный SSH-ключ, которым runner входит на edge-ноду как `team`. В workflow он передаётся в переменную `private_key` и записывается во временный файл на runner
2. `KNOWN_HOSTS`: проверенная запись `known_hosts` для edge-ноды `171.22.72.225`

## Запуск

1. В репо должны быть заданы секреты для Actions
2. Оставаясь в репо, надо перейти на вкладку `Actions`, далее из списка выбрать `autodeploy-hdfs`
3. Нажать `Run workflow`, выбрать ветку `master` и ждать результата. Можно поэтапно наблюдать за логами

Повторный запуск сохраняет имеющиеся каталоги с данными, в таком случае форматирование не выполняется, он ведет только к рестарту отдельных нод.