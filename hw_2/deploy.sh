#!/usr/bin/env bash
set -euo pipefail
EDGE_NODE="team-14-en"
NAMENODE="team-14-nn"
SSH_KEY="$HOME/.ssh/team_internal"

DATANODES=(
    "team-14-00"
    "team-14-01"
    "$EDGE_NODE"
)

NODES=(
    "$EDGE_NODE"
    "$NAMENODE"
    "team-14-00"
    "team-14-01"
)

#Тут проверочка что мы деплоимся на эдж ноде
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


func_on_node() {
    local node="$1"
    if [[ "$node" == "$EDGE_NODE" ]]; then
        bash -s
    else
        ssh -i "$SSH_KEY" \
            -o BatchMode=yes \
            -o StrictHostKeyChecking=accept-new \
            -o ConnectTimeout=10 \
            "team@$node" \
            'bash -s'

    fi
}

for node in "${NODES[@]}"; do
    echo "проверка ноды $node"
    func_on_node "$node" <<'END'
        set -euo pipefail
        sudo -n true
        echo "Имя машины:"
        hostname

        echo "Операционная система:"
        cat /etc/os-release

        echo "Архитектура:"
        uname -m

        echo "Оперативная память:"
        free -h

        echo "Свободное место:"
        df -h /
END
done

echo "Проверили все узлы"

for node in "${NODES[@]}"; do
    echo "Ставим java и hadoop на $node"
    func_on_node "$node" <<'END'
        set -euo pipefail
        HADOOP_VERSION="3.5.0"
        HADOOP_HOME="$HOME/hadoop-$HADOOP_VERSION"
        HADOOP_SHA512="04ab94496cc00c8b7a28d03f6308eff8d2a4e7f37a9da5e8e086e4d6fc990e7a94d661908f6a6136039536efb362614b8aecdef185b5fb8ed588f0b152c7aa16"
        if [[ "$(uname -m)" != "x86_64" ]]; then
            echo "скрипт рассчитан на архитектуру x86_64" >&2
            exit 1
        fi
        sudo -n apt-get update
        sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        openjdk-17-jdk-headless curl ca-certificates tar gzip


        export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
        if [[ ! -e "$HADOOP_HOME" ]]; then
            temp_d="$(mktemp -d "$HOME/.hadoop-install.XXXXXX")"
            trap 'rm -rf "$temp_d"' EXIT
            archive="$temp_d/hadoop-$HADOOP_VERSION.tar.gz"
            curl -fL --retry 10 \
            "https://downloads.apache.org/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz" \
            -o "$archive"
            printf '%s  %s\n' "$HADOOP_SHA512" "$archive" | sha512sum -c -
            tar -xzf "$archive" -C "$temp_d"
            mv "$temp_d/hadoop-$HADOOP_VERSION" "$HADOOP_HOME"
        fi
        "$HADOOP_HOME/bin/hadoop" version
END
done



HADOOP_HOME="$HOME/hadoop-3.5.0"
HDFS_DIR="$HOME/hdfs"
NAMENODE_IP="10.14.0.11"

for node in "${NODES[@]}"; do
    case "$node" in
        team-14-en) node_ip="10.14.0.10" ;;
        team-14-nn) node_ip="10.14.0.11" ;;
        team-14-01) node_ip="10.14.0.13" ;;
        team-14-00) node_ip="10.14.0.12" ;;
        *) echo "неизвестаня нода $node">&2; exit 1 ;;
    esac
    echo "настраиваем hadoop на $node"
    func_on_node "$node" <<END
    set -euo pipefail
    mkdir -p "$HDFS_DIR/name" "$HDFS_DIR/data" "$HDFS_DIR/checkpoint" "$HDFS_DIR/tmp" "$HDFS_DIR/logs" "$HDFS_DIR/pids"
    cat > "$HADOOP_HOME/etc/hadoop/hadoop-env.sh" <<'DOG'
        export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
        export HADOOP_LOG_DIR="$HDFS_DIR/logs"
        export HADOOP_PID_DIR="$HDFS_DIR/pids"
        export HADOOP_HEAPSIZE_MAX="512m"
DOG
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
            <name>dfs.namenode.checkpoint.period</name>
            <value>60</value>
        </property>
        <property>
            <name>dfs.namenode.rpc-bind-host</name>
            <value>0.0.0.0</value>
        </property>
        <property>
            <name>dfs.namenode.http-bind-host</name>
            <value>0.0.0.0</value>
        </property>
    </configuration>
DOGGIK
END
done




namenode_status="$(func_on_node "$NAMENODE" <<HELLO
    set -euo pipefail

    if [[ -f "$HDFS_DIR/name/current/VERSION" ]]; then
        echo "initialized"
    else
        echo "new"
    fi
HELLO
)"

if [[ "$namenode_status" == "new" ]]; then
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

    func_on_node "$NAMENODE" <<BYEBYE
    set -euo pipefail
    "$HADOOP_HOME/bin/hdfs" namenode -format -nonInteractive
BYEBYE
fi


#Теперь запускаем демоны
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

for node in "${DATANODES[@]}"; do
    daemons_restart "$node" "datanode"
done

daemons_restart "$NAMENODE" "secondarynamenode"


assert_ok=false

for i in {1..10}; do
    if result="$(timeout 20 "$HADOOP_HOME/bin/hdfs" dfsadmin -report -live -dead)" && [[ "$result" == *"Live datanodes (3):"* && "$result" == *"Dead datanodes (0):"* ]]; then
        assert_ok=true
        break
    fi
    echo "ждем подтверждения жизнеспособности всех 3 датанод, попытка $i"
    sleep 5
done

printf "%s\n" "$result"

if [[ "$assert_ok" != true ]]; then
    echo "не все датаноды живы" >&2
    exit 1
fi

timeout 300 "$HADOOP_HOME/bin/hdfs" dfsadmin -safemode wait

func_on_node "$NAMENODE"<<'PROVERKA'
    curl -fsS --max-time 60 -o /dev/null http://team-14-nn:9868/
PROVERKA
echo "hadoop успешно развернут и работает"

echo "теперь настраиваем yarn"
YARN_RM="$NAMENODE"
JOB_HISTORY_SERVER="$NAMENODE"
NODEMANAGERS=("${DATANODES[@]}")

for node in "${NODES[@]}"; do
    echo "настраиваем yarn на $node"
    func_on_node "$node" <<OVER
        set -euo pipefail
        cat > "$HADOOP_HOME/etc/hadoop/yarn-site.xml" <<'YARN'
<configuration>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>$YARN_RM</value>
    </property>
    <property>
        <name>yarn.resourcemanager.bind-host</name>
        <value>0.0.0.0</value>
    </property>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.nodemanager.aux-services.mapreduce_shuffle.class</name>
        <value>org.apache.hadoop.mapred.ShuffleHandler</value>
    </property>
    <property>
        <name>yarn.nodemanager.bind-host</name>
        <value>0.0.0.0</value>
    </property>
    <property>
        <name>yarn.nodemanager.resource.memory-mb</name>
        <value>1024</value>
    </property>
    <property>
        <name>yarn.nodemanager.resource.cpu-vcores</name>
        <value>1</value>
    </property>
    <property>
        <name>yarn.scheduler.minimum-allocation-mb</name>
        <value>1024</value>
    </property>
    <property>
        <name>yarn.scheduler.minimum-allocation-vcores</name>
        <value>1</value>
    </property>
    <property>
        <name>yarn.scheduler.maximum-allocation-mb</name>
        <value>1024</value>
    </property>
    <property>
        <name>yarn.scheduler.maximum-allocation-vcores</name>
        <value>1</value>
    </property>
</configuration>
YARN
OVER
done

for node in "${NODES[@]}"; do
    echo "настройка mapreduce на $node"
        func_on_node "$node" <<ENDING
            set -euo pipefail
            cat > "$HADOOP_HOME/etc/hadoop/mapred-site.xml" <<'PRIVET'
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
    <property>
        <name>mapreduce.jobhistory.address</name>
        <value>10.14.0.11:10020</value>
    </property>
    <property>
        <name>mapreduce.jobhistory.webapp.address</name>
        <value>10.14.0.11:19888</value>
    </property>
    <property>
        <name>yarn.app.mapreduce.am.resource.mb</name>
        <value>1024</value>
    </property>

    <property>
        <name>yarn.app.mapreduce.am.resource.vcores</name>
        <value>1</value>
    </property>

    <property>
        <name>mapreduce.map.memory.mb</name>
        <value>1024</value>
    </property>

    <property>
        <name>mapreduce.reduce.memory.mb</name>
        <value>1024</value>
    </property>
</configuration>
PRIVET
ENDING
done


restart_yarn_daemon() {
    local node="$1"
    local folder="$2"
    local daemon="$3"
    echo "перезапуск $daemon на $node"
    func_on_node "$node" <<ENDIKK
        set -euo pipefail
        "$HADOOP_HOME/bin/$folder" --daemon stop "$daemon"
        "$HADOOP_HOME/bin/$folder" --daemon start "$daemon"
ENDIKK
}


echo "запуск resource manager"
restart_yarn_daemon "$YARN_RM" "yarn" "resourcemanager"
echo "запуск job history server"
restart_yarn_daemon "$JOB_HISTORY_SERVER" "mapred" "historyserver"

for node in "${NODEMANAGERS[@]}"; do
    echo "запуск node manager на $node"
    restart_yarn_daemon "$node" "yarn" "nodemanager"
done

echo "проверка работоспособности yarn"
yarn_nodes=""
resultik=0

for attempt in {1..10}; do
    if yarn_nodes="$("$HADOOP_HOME/bin/yarn" node -list -all 2>&1)"; then
        resultik="$(
            printf '%s\n' "$yarn_nodes" |
                awk '$2 == "RUNNING" { count++ } END { print count + 0 }'
        )"

        if [[ "$resultik" -eq "${#NODEMANAGERS[@]}" ]]; then
            break
        fi
    fi

    echo "существует nodemanagers: $resultik, ожидаем ${#NODEMANAGERS[@]}"
    sleep 5
done

if [[ "$resultik" -ne "${#NODEMANAGERS[@]}" ]]; then
    echo "не все nodemanagers сообщили о себе в rm" >&2
    printf '%s\n' "$yarn_nodes" >&2
    exit 1
fi

printf '%s\n' "$yarn_nodes"
echo "все nodemanagers зарегистрированы и находятся в состоянии running"
