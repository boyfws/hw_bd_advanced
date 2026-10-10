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
if [[ "$(hostname -s)" != "$EDGE_NODE"]]; then
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
            printf '%s %s\n' "#HADOOP_SHA512" "$archive" | sha512sum -c -
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
    func_on_node "$node" <<'END'
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
            <name></name>
            <value></value>
        </property>
        <property>
            <name></name>
            <value></value>
        </property>
    </configuration>
DOGGIK


END
done


