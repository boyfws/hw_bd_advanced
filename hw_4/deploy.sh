#!/usr/bin/env bash
set -euo pipefail
umask 077

# Запускается НА EDGE, а не на runner GitHub Actions.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export HADOOP_HOME="$HOME/hadoop-3.5.0"
export HIVE_HOME="$HOME/apache-hive-4.1.0-bin"
SPARK_VERSION=4.2.0
SPARK_SHA512=3a6559e8546ff387db8fe7a04b8fe4008853b467b972c2e343df8e14a81450534777719fc5d4998dd96519a86fdf9de140cee753c61e2e94db044d5f9555ddc4
export SPARK_HOME="$HOME/spark-$SPARK_VERSION-bin-hadoop3"
export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
export PATH="$JAVA_HOME/bin:$HADOOP_HOME/bin:$PATH"
export PYSPARK_PYTHON=/usr/bin/python3
export PYSPARK_DRIVER_PYTHON=/usr/bin/python3
HDFS=hdfs://10.14.0.11:8020
INPUT="$HDFS/user/team/hw3/raw_transactions/transactions.csv"
RESULTS="$SCRIPT_DIR/results"
mkdir -p "$RESULTS"
exec > >(tee "$RESULTS/deploy.log") 2>&1

test "$(id -un)" = team
test "$(hostname -s)" = team-14-en
test -x "$JAVA_HOME/bin/java"
test -x "$HIVE_HOME/bin/beeline"
test -x "$HADOOP_HOME/bin/yarn"
for command in curl tar sha512sum timeout flock python3; do
    command -v "$command" >/dev/null
done
python3 -c 'import sys; assert sys.version_info >= (3, 10), "Нужен Python >= 3.10"'

# Один ручной запуск и один workflow не должны одновременно перезаписывать таблицу.
exec 9> "$HOME/.hw4-deploy.lock"
flock -n 9 || { echo "Другой запуск ДЗ-4 ещё работает" >&2; exit 1; }
TEMP_DIR="$(mktemp -d "$HOME/.hw4.XXXXXX")"
cleanup() {
    local status=$?
    trap - EXIT
    if [[ $status -ne 0 && -s "$RESULTS/application-id.txt" ]]; then
        local app
        app="$(cat "$RESULTS/application-id.txt")"
        if [[ "$app" =~ ^application_[0-9]+_[0-9]+$ ]]; then
            timeout 30 yarn application -status "$app" > "$RESULTS/yarn-status.txt" 2>&1 || true
            timeout 30 yarn application -kill "$app" >> "$RESULTS/yarn-status.txt" 2>&1 || true
        fi
    fi
    rm -rf -- "$TEMP_DIR"
    if [[ $status -ne 0 ]]; then echo "ДЗ-4 завершилось ошибкой ($status). См. results/deploy.log" >&2; fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# results относится к этому запуску; старый application id нельзя использовать при ошибке.
rm -f "$RESULTS/application-id.txt" "$RESULTS/spark-report.json" "$RESULTS/hive-report.json"

echo "Проверка существующих HDFS, YARN и Hive"
timeout 300 hdfs dfsadmin -safemode wait
timeout 30 hdfs dfsadmin -report > "$RESULTS/hdfs-report.txt"
timeout 30 yarn node -list -all > "$RESULTS/yarn-nodes.txt"
cat "$RESULTS/yarn-nodes.txt"

beeline() {
    HIVE_CONF_DIR="$HIVE_HOME/conf" timeout --kill-after=10s 180 \
        "$HIVE_HOME/bin/beeline" \
        -u jdbc:hive2://127.0.0.1:10000/default -n team \
        --silent=true --showHeader=false --outputformat=tsv2 --force=false "$@"
}
beeline -e 'SHOW DATABASES;' > "$RESULTS/hive-databases.txt"

echo "Подготовка входного CSV в HDFS"
if ! timeout 30 hdfs dfs -test -e "$INPUT"; then
    test -s "$SCRIPT_DIR/../hw_3/transactions.csv"
    timeout 30 hdfs dfs -mkdir -p "$HDFS/user/team/hw3/raw_transactions"
    # Без -f: существующие исходные данные не перезаписываем.
    timeout 30 hdfs dfs -put "$SCRIPT_DIR/../hw_3/transactions.csv" "$INPUT"
fi
timeout 30 hdfs dfs -cat "$INPUT" > "$RESULTS/input.csv"
test -s "$RESULTS/input.csv"
timeout 30 hdfs dfs -checksum "$INPUT" > "$RESULTS/input-checksum-before.txt"

echo "Подготовка Spark $SPARK_VERSION"
if [[ ! -e "$SPARK_HOME" ]]; then
    archive="spark-$SPARK_VERSION-bin-hadoop3.tgz"
    if ! curl -fL --connect-timeout 15 --max-time 900 --retry 3 \
        "https://downloads.apache.org/spark/spark-$SPARK_VERSION/$archive" \
        -o "$TEMP_DIR/$archive"; then
        curl -fL --connect-timeout 15 --max-time 900 --retry 3 \
            "https://archive.apache.org/dist/spark/spark-$SPARK_VERSION/$archive" \
            -o "$TEMP_DIR/$archive"
    fi
    printf '%s  %s\n' "$SPARK_SHA512" "$TEMP_DIR/$archive" | sha512sum -c -
    tar -xzf "$TEMP_DIR/$archive" -C "$TEMP_DIR"
    printf '%s\n' "$SPARK_SHA512" > "$TEMP_DIR/spark-$SPARK_VERSION-bin-hadoop3/.hw4-sha512"
    mv "$TEMP_DIR/spark-$SPARK_VERSION-bin-hadoop3" "$SPARK_HOME"
fi
test -x "$SPARK_HOME/bin/spark-submit"
if [[ ! -f "$SPARK_HOME/.hw4-sha512" ]] || [[ "$(cat "$SPARK_HOME/.hw4-sha512")" != "$SPARK_SHA512" ]]; then
    echo "Spark уже существует, но установлен не этим скриптом. Проверьте каталог $SPARK_HOME" >&2
    exit 1
fi

# Не наследуем Tez, пароли PostgreSQL и настройки HiveServer2 в Spark.
unset HADOOP_CLASSPATH SPARK_DIST_CLASSPATH SPARK_SUBMIT_OPTS PYSPARK_SUBMIT_ARGS
export SPARK_CONF_DIR="$TEMP_DIR/spark-conf"
export HIVE_CONF_DIR="$SPARK_CONF_DIR"
mkdir -p "$SPARK_CONF_DIR" "$TEMP_DIR/hadoop-conf"
for file in core-site.xml hdfs-site.xml yarn-site.xml; do
    cp "$HADOOP_CONF_DIR/$file" "$TEMP_DIR/hadoop-conf/$file"
done
export HADOOP_CONF_DIR="$TEMP_DIR/hadoop-conf"
export YARN_CONF_DIR="$HADOOP_CONF_DIR"
cat > "$SPARK_CONF_DIR/hive-site.xml" <<'XML'
<?xml version="1.0"?>
<configuration>
  <property><name>hive.metastore.uris</name><value>thrift://10.14.0.12:9083</value></property>
  <property><name>hive.metastore.warehouse.dir</name><value>hdfs://10.14.0.11:8020/user/hive/warehouse</value></property>
</configuration>
XML

# Код Python хранится здесь, временный файл нужен для spark-submit.
cat > "$TEMP_DIR/spark_job.py" <<'SPARK_PY'
"""Преобразования выполняются Spark SQL на executors, без Python UDF."""

from pyspark.sql import functions as F
from pyspark.sql.types import StringType, StructField, StructType
from urllib.parse import urlsplit
import re

COLUMNS = ["transaction_id", "customer_id", "amount", "category", "transaction_year"]


def read_transactions(spark, path):
    # Сначала строки: ошибки преобразования проверяем явно, а не теряем молча.
    schema = StructType([StructField(name, StringType()) for name in COLUMNS])
    raw = (spark.read.schema(schema).option("header", True)
           .option("enforceSchema", False).option("mode", "FAILFAST").csv(path))
    return raw.select(
        F.expr("try_cast(transaction_id AS INT)").alias("transaction_id"),
        F.expr("try_cast(customer_id AS INT)").alias("customer_id"),
        F.expr("try_cast(amount AS DECIMAL(18,2))").alias("amount"),
        F.lower(F.trim("category")).alias("category"),
        F.expr("try_cast(transaction_year AS INT)").alias("transaction_year"),
        F.trim("amount").rlike(r"^[0-9]+(\.[0-9]{1,2})?$").alias("valid_money"),
    )


def validate_transactions(df):
    valid = (
        (F.col("transaction_id") > 0) & (F.col("customer_id") > 0)
        & (F.col("amount") >= 0) & F.col("valid_money")
        & F.col("category").rlike(r"^[a-z][a-z0-9_-]*$")
        & F.col("transaction_year").between(1900, 2100)
    )
    invalid = df.filter(~F.coalesce(valid, F.lit(False))).count()
    if invalid:
        raise ValueError(f"Некорректных строк: {invalid}; таблица не изменена")
    stats = df.agg(F.count("*").alias("rows"),
                   F.countDistinct("transaction_id").alias("ids")).first()
    if stats.rows == 0:
        raise ValueError("Входной CSV пуст")
    if stats.rows != stats.ids:
        raise ValueError("Повторяются transaction_id")
    return stats.rows


def summarize(df):
    return (df.groupBy("transaction_year", "category").agg(
        F.count("*").alias("transaction_count"),
        F.countDistinct("customer_id").alias("customer_count"),
        F.sum("amount").cast("decimal(20,2)").alias("total_amount"),
        F.avg("amount").cast("decimal(20,2)").alias("avg_amount"),
    ).select("category", "transaction_count", "customer_count",
             "total_amount", "avg_amount", "transaction_year"))


def save_summary(spark, summary, table, output_uri):
    # Повторный запуск может перезаписать только нашу внешнюю таблицу по этому пути.
    if spark.catalog.tableExists(table):
        details = {r.col_name: r.data_type
                   for r in spark.sql(f"DESCRIBE TABLE EXTENDED {table}").collect()}
        if (urlsplit(details.get("Location", "").rstrip("/")) != urlsplit(output_uri.rstrip("/"))
                or details.get("Type") != "EXTERNAL"
                or details.get("Provider") != "hive"):
            raise ValueError(f"{table} существует с другой конфигурацией; остановка")
    # Hive SerDe + Parquet: таблица читается обычным Hive, а не только Spark.
    (summary.write.mode("overwrite").format("hive")
     .option("fileFormat", "parquet").option("path", output_uri)
     .partitionBy("transaction_year").saveAsTable(table))
    # При пересоздании EXTERNAL-таблицы Spark оставляет каталоги исчезнувших
    # партиций. Удаляем только такие каталоги внутри выделенного пути ДЗ-4,
    # иначе последующий MSCK REPAIR мог бы вернуть старые данные в таблицу.
    live_partitions = {row[0] for row in spark.sql(f"SHOW PARTITIONS {table}").collect()}
    path = spark._jvm.org.apache.hadoop.fs.Path(output_uri)
    fs = path.getFileSystem(spark.sparkContext._jsc.hadoopConfiguration())
    for status in fs.listStatus(path):
        name = status.getPath().getName()
        if status.isDirectory() and re.fullmatch(r"transaction_year=[0-9]+", name) and name not in live_partitions:
            if not fs.delete(status.getPath(), True):
                raise RuntimeError(f"Не удалось удалить устаревшую партицию: {name}")


"""ДЗ-4: HDFS -> Spark on YARN -> партиционированная Hive-таблица."""

import argparse
import json
from pathlib import Path

from pyspark.sql import SparkSession


HDFS = "hdfs://10.14.0.11:8020"
INPUT = HDFS + "/user/team/hw3/raw_transactions/transactions.csv"
OUTPUT = HDFS + "/user/team/hw4/transaction_summary"
TABLE = "hw4.transaction_summary"
METASTORE = "thrift://10.14.0.12:9083"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", required=True)
    parser.add_argument("--application-id-file", required=True)
    args = parser.parse_args()
    spark = SparkSession.builder.appName("hw4-transaction-summary").enableHiveSupport().getOrCreate()
    spark.sparkContext.setLogLevel("WARN")
    try:
        sc = spark.sparkContext
        if sc.master != "yarn" or not sc.applicationId.startswith("application_"):
            raise RuntimeError("Задание нужно запускать через spark-submit --master yarn")
        if sc._jsc.hadoopConfiguration().get("hive.metastore.uris") != METASTORE:
            raise RuntimeError("Не настроен общий Hive Metastore; локальный Derby запрещён")
        print(f"YARN_APPLICATION_ID={sc.applicationId}", flush=True)
        Path(args.application_id_file).write_text(sc.applicationId + "\n")
        df = read_transactions(spark, INPUT).cache()
        input_rows = validate_transactions(df)
        summary = summarize(df).cache()
        expected = summary.collect()
        spark.sql("CREATE DATABASE IF NOT EXISTS hw4")
        save_summary(spark, summary, TABLE, OUTPUT)

        actual = spark.table(TABLE).collect()
        if set(actual) != set(expected):
            raise RuntimeError("Spark не прочитал записанные данные без изменений")
        partitions = [r[0] for r in spark.sql(f"SHOW PARTITIONS {TABLE}").collect()]
        years = sorted({r.transaction_year for r in expected})
        if sorted(partitions) != [f"transaction_year={year}" for year in years]:
            raise RuntimeError("Набор партиций не совпал с исходными годами")
        total = df.agg(F.sum("amount")).first()[0]
        if sum(r.transaction_count for r in actual) != input_rows or sum(r.total_amount for r in actual) != total:
            raise RuntimeError("При агрегации потерялись строки или денежная сумма")
        report = {
            "application_id": sc.applicationId, "master": sc.master,
            "spark_version": spark.version, "metastore": METASTORE,
            "input": INPUT, "table": TABLE, "output": OUTPUT,
            "input_rows": input_rows, "output_rows": len(actual),
            "partitions": sorted(partitions), "total_amount": str(total),
        }
        Path(args.report).write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2), flush=True)
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
SPARK_PY

echo "запск преобразований в yarn"
timeout --kill-after=30s 1800 "$SPARK_HOME/bin/spark-submit" \
    --master yarn --deploy-mode client \
    --name hw4-transaction-summary \
    --driver-memory 768m --executor-memory 512m --executor-cores 1 --num-executors 1 \
    --conf spark.executor.memoryOverhead=384m \
    --conf spark.yarn.am.memory=512m --conf spark.yarn.am.memoryOverhead=384m \
    --conf spark.yarn.am.cores=1 --conf spark.yarn.maxAppAttempts=1 \
    --conf 'spark.executor.extraJavaOptions=-XX:CompressedClassSpaceSize=64m -XX:ReservedCodeCacheSize=128m' \
    --conf 'spark.yarn.am.extraJavaOptions=-XX:CompressedClassSpaceSize=64m -XX:ReservedCodeCacheSize=128m' \
    --conf spark.executorEnv.MALLOC_ARENA_MAX=2 \
    --conf spark.yarn.appMasterEnv.MALLOC_ARENA_MAX=2 \
    --conf spark.dynamicAllocation.enabled=false \
    --conf spark.driver.host=10.14.0.10 --conf spark.driver.bindAddress=0.0.0.0 \
    --conf spark.driver.maxResultSize=32m \
    --conf spark.sql.shuffle.partitions=2 --conf spark.default.parallelism=2 \
    --conf spark.sql.catalogImplementation=hive \
    --conf spark.sql.hive.metastore.version=4.1.0 \
    --conf spark.sql.hive.metastore.jars=maven \
    --conf spark.sql.warehouse.dir="$HDFS/user/hive/warehouse" \
    --conf spark.hadoop.fs.defaultFS="$HDFS" \
    --conf spark.hadoop.hive.metastore.uris=thrift://10.14.0.12:9083 \
    --conf spark.hadoop.hive.exec.dynamic.partition=true \
    --conf spark.hadoop.hive.exec.dynamic.partition.mode=nonstrict \
    --conf spark.sql.sources.partitionOverwriteMode=static \
    "$TEMP_DIR/spark_job.py" --report "$RESULTS/spark-report.json" \
    --application-id-file "$RESULTS/application-id.txt"

app="$(cat "$RESULTS/application-id.txt")"
timeout 30 yarn application -status "$app" > "$RESULTS/yarn-status.txt"
for attempt in {1..12}; do
    if grep -Eq 'Final-State[[:space:]]*:[[:space:]]*SUCCEEDED' "$RESULTS/yarn-status.txt"; then break; fi
    echo "Ожидаем финальный статус yarn: $attempt/12"
    sleep 5
    timeout 30 yarn application -status "$app" > "$RESULTS/yarn-status.txt"
done
grep -Eq 'Final-State[[:space:]]*:[[:space:]]*SUCCEEDED' "$RESULTS/yarn-status.txt"
timeout 30 hdfs dfs -checksum "$INPUT" > "$RESULTS/input-checksum-after.txt"
cmp "$RESULTS/input-checksum-before.txt" "$RESULTS/input-checksum-after.txt"

beeline -e '
SET hive.fetch.task.conversion=more;
SET hive.fetch.task.conversion.threshold=-1;
SELECT category, transaction_count, customer_count,
       total_amount, avg_amount, transaction_year
FROM hw4.transaction_summary;
' > "$RESULTS/hive-rows.tsv"
beeline -e 'SHOW PARTITIONS hw4.transaction_summary;' > "$RESULTS/hive-partitions.txt"
beeline -e 'DESCRIBE FORMATTED hw4.transaction_summary;' > "$RESULTS/hive-table.txt"
python3 - "$RESULTS/input.csv" "$RESULTS/hive-rows.tsv" \
    "$RESULTS/hive-partitions.txt" "$RESULTS/hive-report.json" <<'VERIFY_PY'

import sys
import csv
import json
from collections import defaultdict
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path


def expected_rows(source):
    groups = defaultdict(list)
    with open(source, newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            key = (int(row["transaction_year"]), row["category"].strip().lower())
            groups[key].append((int(row["customer_id"]), Decimal(row["amount"])))
    result = {}
    for key, rows in groups.items():
        total = sum((amount for _, amount in rows), Decimal(0))
        average = (total / len(rows)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        result[key] = (len(rows), len({customer for customer, _ in rows}), total, average)
    return result


def verify(source, beeline_file, partitions_file):
    expected = expected_rows(source)
    actual = {}
    with open(beeline_file, newline="", encoding="utf-8") as stream:
        for row in csv.reader(stream, delimiter="\t"):
            if not row:
                continue
            if len(row) != 6:
                raise ValueError(f"Ожидалось 6 столбцов Beeline, получено {len(row)}")
            category, count, customers, total, average, year = row
            key = (int(year), category)
            if key in actual:
                raise ValueError(f"Повторная группа в Hive: {key}")
            actual[key] = (int(count), int(customers), Decimal(total), Decimal(average))
    if not expected or actual != expected:
        raise ValueError(f"Результат hive отличается от csv")
    partitions = [line.strip() for line in Path(partitions_file).read_text().splitlines() if line.strip()]
    wanted = sorted({f"transaction_year={year}" for year, _ in expected})
    if sorted(partitions) != wanted:
        raise ValueError(f"некорректные партиции hive: {partitions}; ожидалось {wanted}")
    return {"hive_read_verified": True, "groups": len(actual), "partitions": wanted,
            "total_amount": str(sum((row[2] for row in actual.values()), Decimal(0)))}


result = verify(sys.argv[1], sys.argv[2], sys.argv[3])
Path(sys.argv[4]).write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
VERIFY_PY
timeout 30 hdfs dfs -ls -R "$HDFS/user/team/hw4/transaction_summary" > "$RESULTS/hdfs-output.txt"