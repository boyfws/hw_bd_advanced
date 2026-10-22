# Автоматизированное развертывание Apache Hive

В этой работе выполняется развертывание Apache Hive с возможностью одновременного подключения нескольких клиентов. Для хранения метаданных используется отдельный Hive Metastore с PostgreSQL, а для подключения клиентов – HiveServer2.

Также подготовлена автоматизированная загрузка CSV-файла в партиционированную таблицу Hive. Установка компонентов, запуск служб и выполнение SQL-команд организованы с помощью GitHub Actions.

## Состав кластера

Для выполнения задания используется Hadoop-кластер, развернутый в предыдущих домашних работах.

1. `team-14-nn`, `10.14.0.11` – NameNode, Secondary NameNode, ResourceManager и JobHistoryServer.
2. `team-14-en`, `10.14.0.10` – edge-нода, DataNode, NodeManager и HiveServer2.
3. `team-14-00`, `10.14.0.12` – DataNode, NodeManager, Hive Metastore и PostgreSQL.
4. `team-14-01`, `10.14.0.13` – DataNode и NodeManager.

Используются Apache Hadoop 3.5.0, Apache Hive 4.1.0, Apache Tez 0.10.5 и PostgreSQL 16.

Hadoop установлен в `$HOME/hadoop-3.5.0`, Hive – в `$HOME/apache-hive-4.1.0-bin`, Tez – в `$HOME/apache-tez-0.10.5-bin`.

Вместо рекомендованной версии Hive 4.0.0-alpha2 используется более поздняя версия 4.1.0.

## Как устроено развертывание

Развертывание состоит из нескольких этапов. GitHub Actions подключается к edge-ноде по SSH, передает необходимые скрипты и выполняет команды на сервере.

Для установки используется ранее подготовленный Hadoop-кластер с работающими HDFS и YARN.

### 1. Подготовка дистрибутивов

Сценарий [prepare-hive.yml](../.github/workflows/prepare-hive.yml) запускает скрипт [prepare_hive.sh](prepare_hive.sh).

Он скачивает архивы Apache Hive 4.1.0 и Apache Tez 0.10.5 в каталог `$HOME/hw3-downloads` и проверяет их целостность с помощью `tar`.

После этого сценарий [unpack-hive.yml](../.github/workflows/unpack-hive.yml) запускает [unpack_hive.sh](unpack_hive.sh), который распаковывает архивы в домашний каталог пользователя `team`.

Если каталоги уже существуют, повторная распаковка не выполняется.

### 2. Установка PostgreSQL

Сценарий [plan-postgres.yml](../.github/workflows/plan-postgres.yml) выполняет установку и первоначальную настройку PostgreSQL на узле `team-14-00`.

Он проверяет наличие PostgreSQL 16, при необходимости устанавливает его и создает базу данных `hive_metastore` и пользователя `hive`.

Также устанавливаются ограничения на использование памяти и количество подключений, поскольку PostgreSQL работает на том же узле, что и службы Hadoop.

### 3. Настройка Hive Metastore

Основной скрипт [deploy.sh](deploy.sh) содержит команды настройки удаленного Hive Metastore.

Metastore использует PostgreSQL для хранения сведений о базах данных, таблицах и партициях. Сервер Metastore работает на узле `team-14-00` и принимает подключения через порт `9083`.

Для подключения к PostgreSQL используется JDBC-драйвер. Настройки сохраняются в `hive-site.xml`.

Поскольку Metastore работает как отдельная служба и использует PostgreSQL, встроенная база Derby в embedded-режиме не применяется.

### 4. Настройка HiveServer2

HiveServer2 размещается на edge-ноде `team-14-en`.

В его конфигурации задаются:

- Адрес Metastore – `thrift://team-14-00:9083`.
- Порт HiveServer2 – `10000`.
- Адрес прослушивания – `127.0.0.1`.
- Движок выполнения запросов – Tez.

Для управления HiveServer2 используется [deploy-hive.yml](../.github/workflows/deploy-hive.yml).

Текущая версия этого сценария запускает `deploy.sh` с аргументом `--restart-hs2-only`. Этот режим настраивает и перезапускает HiveServer2 на уже подготовленном кластере, не перезапуская HDFS, YARN, PostgreSQL и Metastore.

Первоначальная настройка Metastore предусмотрена основной частью `deploy.sh`, но полный процесс установки Hive с нуля одним запуском GitHub Actions не проверялся.

## Проверка одновременного подключения клиентов

Для подключения используется клиент Beeline.

```bash
beeline -u "jdbc:hive2://127.0.0.1:10000/default"
```

Для проверки многопользовательского доступа подготовлен сценарий [check-hiveserver2-log.yml](../.github/workflows/check-hiveserver2-log.yml).

Он одновременно запускает два независимых клиента Beeline. Каждый подключается к одному экземпляру HiveServer2 и выполняет SQL-команду:

```sql
SHOW DATABASES;
```

Оба клиента запускаются параллельно, после чего сценарий ожидает завершения каждого процесса и проверяет результат.

Запуск `Check HiveServer2 Log #14` в GitHub Actions завершился успешно.

Таким образом, подтверждена возможность параллельного подключения двух клиентов к HiveServer2.

## Подготовка Apache Tez

Для выполнения вычислительных заданий подготовлен Apache Tez 0.10.5.

Сценарий [setup-tez.yml](../.github/workflows/setup-tez.yml) запускает [setup_tez.sh](setup_tez.sh), который размещает архив Tez в HDFS по пути:

```text
/apps/tez/tez-0.10.5.tar.gz
```

Скрипт также создает конфигурационный файл `tez-site.xml` с адресом архива в HDFS.

Дополнительно выполняется [configure_hive_tez.sh](configure_hive_tez.sh), который подготавливает конфигурацию Tez для Hive.

В процессе проверки вычислительных запросов возникла ошибка запуска Tez в YARN, описанная ниже.

## Автоматизированная загрузка данных

В качестве исходных данных используется файл [transactions.csv](transactions.csv), содержащий 12 записей о транзакциях.

CSV загружается в HDFS по пути:

```text
/user/team/hw3/raw_transactions/transactions.csv
```

Загрузка исходного файла предусмотрена сценарием `setup-tez.yml`.

### Создание таблиц

Файл [create_table.sql](create_table.sql) создает базу данных `hw3` и внешнюю таблицу `transactions`.

Таблица содержит следующие поля:

- `transaction_id` – идентификатор транзакции.
- `customer_id` – идентификатор клиента.
- `amount` – сумма транзакции.
- `category` – категория транзакции.
- `transaction_year` – год транзакции, используемый для партиционирования.

Таблица создается в формате Parquet:

```sql
CREATE DATABASE IF NOT EXISTS hw3;

USE hw3;

CREATE EXTERNAL TABLE IF NOT EXISTS transactions (
    transaction_id INT,
    customer_id INT,
    amount DOUBLE,
    category STRING
)
PARTITIONED BY (transaction_year INT)
STORED AS PARQUET;
```

Партиционирование позволяет разделять данные по годам и при необходимости выполнять запросы только к соответствующим разделам таблицы.

### Загрузка CSV

Файл [load_data.sql](load_data.sql) создает промежуточную текстовую таблицу `transactions_raw`, которая читает исходный CSV из HDFS.

Затем выполняется перенос данных в партиционированную таблицу:

```sql
INSERT OVERWRITE TABLE transactions
PARTITION (transaction_year)
SELECT
    transaction_id,
    customer_id,
    amount,
    category,
    transaction_year
FROM transactions_raw
WHERE transaction_id IS NOT NULL;
```

Для этой операции SQL-скрипт устанавливает движок выполнения `mr`, то есть MapReduce.

Автоматизированный запуск SQL-команд выполняется через сценарий [load-hive-data.yml](../.github/workflows/load-hive-data.yml).

Он передает SQL-файлы на edge-ноду, создает таблицы через Beeline, выполняет загрузку данных и содержит заключительную проверку результата.

Дополнительно представлен [load_data.sh](load_data.sh), который объединяет загрузку CSV в HDFS, создание таблиц и выполнение SQL-файлов. Этот скрипт является отдельным способом запуска и не вызывается текущим сценарием GitHub Actions.

## Проверка результата загрузки

Для проверки количества записей и созданных партиций используются следующие SQL-команды:

```sql
USE hw3;

SELECT COUNT(*) FROM transactions;

SHOW PARTITIONS transactions;

SELECT transaction_year, COUNT(*)
FROM transactions
GROUP BY transaction_year
ORDER BY transaction_year;
```

Ожидаемый результат – 12 записей, распределенных по трем партициям: 2024, 2025 и 2026.

### Обнаруженные ограничения

Создание таблиц и размещение исходного CSV в HDFS были выполнены успешно. Однако запись данных в партиционированную таблицу завершалась ошибкой вычислительного задания.

При использовании Tez возникала ошибка:

```text
ClassNotFoundException:
org.apache.tez.dag.app.DAGAppMaster
```

При переключении на MapReduce задание отправлялось в YARN, но завершалось с ошибкой выполнения.

Поэтому успешное заполнение таблицы `transactions` и создание партиций пока не подтверждены. SQL-команды, автоматизированный сценарий и исходные данные сохранены в репозитории для воспроизведения загрузки после устранения проблемы.

## Запуск через GitHub Actions

Все сценарии находятся в каталоге `.github/workflows/` и запускаются вручную через `workflow_dispatch`.

Для запуска необходимо открыть вкладку **Actions** в GitHub, выбрать сценарий, нажать **Run workflow** и выбрать ветку `master`.

Сценарии, относящиеся к домашнему заданию №3:

1. [prepare-hive.yml](../.github/workflows/prepare-hive.yml) – скачивание архивов Hive и Tez.
2. [unpack-hive.yml](../.github/workflows/unpack-hive.yml) – распаковка дистрибутивов.
3. [plan-postgres.yml](../.github/workflows/plan-postgres.yml) – установка и подготовка PostgreSQL.
4. [deploy-hive.yml](../.github/workflows/deploy-hive.yml) – настройка и перезапуск HiveServer2 на подготовленном кластере.
5. [setup-tez.yml](../.github/workflows/setup-tez.yml) – настройка Tez и загрузка исходного CSV в HDFS.
6. [load-hive-data.yml](../.github/workflows/load-hive-data.yml) – создание таблиц и выполнение SQL-загрузки.
7. [check-hiveserver2-log.yml](../.github/workflows/check-hiveserver2-log.yml) – проверка двух параллельных клиентов.

Предварительно необходимы работающие HDFS и YARN, подготовленная база Metastore и настройки доступа между узлами. Начальную настройку Metastore нельзя заменить простым запуском `deploy-hive.yml` в его текущем режиме перезапуска.

В репозитории также сохранены `deploy-hdfs.yml` и `deploy-yarn.yml`, относящиеся к предыдущим домашним заданиям.

Для подключения к серверам используются GitHub Secrets:

1. `SSH_PRIVATE` – приватный SSH-ключ для подключения к edge-ноде.
2. `KNOWN_HOSTS` – проверенные сведения о SSH-хосте.
3. `HIVE_DB_PASSWORD` – пароль пользователя PostgreSQL для Hive.

Значения секретов не хранятся в открытых файлах репозитория.

## Итог

В работе развернут Apache Hive 4.1.0 с отдельным Hive Metastore на PostgreSQL и HiveServer2. Embedded-режим не используется.
Успешно проверена возможность параллельного подключения двух клиентов Beeline к одному серверу HiveServer2.
Подготовлены скрипты установки, конфигурирования и запуска компонентов Hive, а также сценарий загрузки данных в партиционированную таблицу. Исходный CSV размещен в HDFS, таблицы созданы.
Ограничением остается ошибка выполнения вычислительного задания при записи данных в партиционированную таблицу. Процедура автоматизированной загрузки описана и реализована в скриптах, но ее успешное выполнение пока не подтверждено.
