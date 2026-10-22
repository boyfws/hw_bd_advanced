# Обработка данных Apache Spark под управлением YARN

Spark читает csv-файл из HDFS, преобразует данные и сохраняет партиционированную таблицу Hive. Запуск выполняется вручную через GitHub Actions. Workflow подключается к edge-ноде и запускает [deploy.sh](./deploy.sh), а вычисления выполняются под управлением YARN.

Для работы используются три файла: `hw_4/deploy.sh`, этот README и [deploy-spark.yml](../.github/workflows/deploy-spark.yml). Python-код обработки и проверки находится внутри `deploy.sh`, временный файл для `spark-submit` создается при запуске и затем удаляется.

## Состав кластера

Используется кластер из предыдущих домашних работ:

1. `team-14-nn`, `10.14.0.11` - NameNode, Secondary NameNode, ResourceManager и JobHistoryServer.
2. `team-14-en`, `10.14.0.10` - edge-нода, DataNode, NodeManager, HiveServer2 и Spark driver.
3. `team-14-00`, `10.14.0.12` - DataNode, NodeManager, Hive Metastore и PostgreSQL.
4. `team-14-01`, `10.14.0.13` - DataNode и NodeManager.

Используются Hadoop, Hive, Spark, Java и Python.

## Как устроено развертывание

Workflow [deploy-spark.yml](../.github/workflows/deploy-spark.yml) запускается вручную через `workflow_dispatch`.

Он выполняет следующие действия:

1. Получает выбранную ветку репозитория.
2. Проверяет синтаксис `hw_4/deploy.sh` командой `bash -n`.
3. Настраивает SSH, используя существующие GitHub Secrets.
4. Передает `deploy.sh` и исходный csv на edge и запускает скрипт.
5. Скачивает отчеты и сохраняет их как артефакт GitHub Actions, в том числе при ошибке, если SSH доступен.

Каждый запуск получает отдельный каталог `$HOME/hw4-runs/<run_id>-<attempt>`.

## Что делает deploy.sh

1. Проверяет пользователя, узел, необходимые программы и доступность HDFS, YARN и HiveServer2.
2. Использует исходный файл `/user/team/hw3/raw_transactions/transactions.csv` в HDFS.
3. Устанавливает Spark в `$HOME/spark-4.2.0-bin-hadoop3`
4. Подключает конфигурацию Hadoop и общий Hive Metastore.
5. Запускает SparkSession под YARN, читает данные и выполняет преобразования.
6. Сохраняет таблицу `hw4.transaction_summary` в parquet с партициями по году.
7. Проверяет результат через Spark, финальный статус YARN и чтение таблицы через Beeline.

## Настройка Spark

Основные параметры запуска:

```bash
--master yarn --deploy-mode client
--driver-memory 768m --executor-memory 512m --executor-cores 1 --num-executors 1
--conf spark.sql.hive.metastore.version=4.1.0
--conf spark.sql.hive.metastore.jars=maven
--conf spark.hadoop.fs.defaultFS=hdfs://10.14.0.11:8020
--conf spark.hadoop.hive.metastore.uris=thrift://10.14.0.12:9083
```

В режиме `client` driver работает на edge, а executor запускается YARN на одном из NodeManager. Driver сообщает внутренний адрес `10.14.0.10`, доступный остальным узлам. 

Для executor и ApplicationMaster выделяется по 512 мб хип и 384 МиБ оверхед. YARN округляет каждый запрос до 1024 мб. Нужны два свободных контейнера и отдельная память для driver на edge.
Сессия создается с поддержкой Hive:

```python
spark = SparkSession.builder.appName("hw4-transaction-summary").enableHiveSupport().getOrCreate()
```

Она использует существующий метастор. Клиентские библиотеки загружаются при первом обращении. Локальный Derby вместо общего метастора в рабочем запуске не используется.

## Чтение и преобразование данных

Spark читает csv из HDFS через `spark.read.csv()`. Идентификаторы и год приводятся к `INT`, сумма - к `DECIMAL(18,2)`. Категории очищаются от пробелов и переводятся в нижний регистр

Далее данные группируются по году и категории:

```python
df.groupBy("transaction_year", "category").agg(
    F.count("*").alias("transaction_count"),
    F.countDistinct("customer_id").alias("customer_count"),
    F.sum("amount").cast("decimal(20,2)").alias("total_amount"),
    F.avg("amount").cast("decimal(20,2)").alias("avg_amount"),
)
```

Для csv ожидаются 12 исходных операций, 11 групп и общая сумма `48931.25`.

## Сохранение таблицы и проверка

Результат записывается как внешняя hive-таблица с parquet:

```python
(summary.write.mode("overwrite").format("hive")
 .option("fileFormat", "parquet").option("path", output_uri)
 .partitionBy("transaction_year").saveAsTable("hw4.transaction_summary"))
```

Данные располагаются в `/user/team/hw4/transaction_summary`, в каталогах `transaction_year=2024`, `transaction_year=2025` и `transaction_year=2026`. Информация о таблице и партициях хранится в общем Metastore.

Spark повторно читает таблицу и проверяет строки, партиции, число операций и сумму. Затем beeline подключается к HiveServer2 на `jdbc:hive2://127.0.0.1:10000/default` и выполняет:

```sql
SET hive.fetch.task.conversion=more;
SET hive.fetch.task.conversion.threshold=-1;
SELECT category, transaction_count, customer_count,
       total_amount, avg_amount, transaction_year
FROM hw4.transaction_summary;
SHOW PARTITIONS hw4.transaction_summary;
```

Все прочитанные через hive группы сравниваются с независимым расчетом по исходному csv.

## Запуск

1. Открыть Actions -  deploy spark on yarn - Run workflow.

В артефакте находятся `deploy.log`, `spark-report.json`, `yarn-status.txt`, `hive-rows.tsv`, `hive-partitions.txt`, `hive-table.txt` и `hive-report.json`. Успешный результат подтверждают `Final-State: SUCCEEDED` в YARN и `hive_read_verified: true` в отчете Hive.

Ручной запуск из копии репозитория на edge, под `team`:

```bash
bash hw_4/deploy.sh
```

После завершения задания Spark освобождает ресурсы, таблица остается в HDFS и метамстор, службы кластера продолжают работать.
