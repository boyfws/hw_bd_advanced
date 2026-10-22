# Автоматизированное развертывание Apache Hive

В этой работе выполняется развертывание Apache Hive с возможностью одновременного подключения нескольких клиентов. Для хранения метаданных используется отдельный Hive Metastore с PostgreSQL, а для подключения клиентов – HiveServer2. Таким образом, встроенный режим Metastore (embedded) не используется.

Также реализована автоматизированная загрузка CSV-файла в партиционированную таблицу Hive. Подготовка компонентов, настройка служб и загрузка данных выполняются с помощью GitHub Actions.

## Состав кластера

Для выполнения задания используется Hadoop-кластер, развернутый в предыдущих домашних работах.

1. `team-14-nn`, `10.14.0.11` – NameNode, Secondary NameNode, ResourceManager и JobHistoryServer.
2. `team-14-en`, `10.14.0.10` – edge-нода, DataNode, NodeManager и HiveServer2.
3. `team-14-00`, `10.14.0.12` – DataNode, NodeManager, Hive Metastore и PostgreSQL.
4. `team-14-01`, `10.14.0.13` – DataNode и NodeManager.

Используются Apache Hadoop 3.5.0, Apache Hive 4.1.0, Apache Tez 0.10.5 и PostgreSQL 16.

Hadoop установлен в `$HOME/hadoop-3.5.0`, Hive – в `$HOME/apache-hive-4.1.0-bin`, Tez – в `$HOME/apache-tez-0.10.5-bin`.

Вместо рекомендованной версии Hive 4.0.0-alpha2 используется версия 4.1.0.

## Как устроено развертывание

Развертывание разделено на несколько этапов. GitHub Actions подключается к edge-ноде по SSH, передает необходимые скрипты и запускает их на сервере.

Предварительно должны работать HDFS и YARN, подготовленные в предыдущих домашних заданиях.

### 1. Подготовка дистрибутивов

Сценарий [prepare-hive.yml](../.github/workflows/prepare-hive.yml) запускает [prepare_hive.sh](prepare_hive.sh).

Скрипт загружает архивы Apache Hive 4.1.0 и Apache Tez 0.10.5 в каталог `$HOME/hw3-downloads` и проверяет возможность чтения архивов с помощью `tar`.

Затем сценарий [unpack-hive.yml](../.github/workflows/unpack-hive.yml) запускает [unpack_hive.sh](unpack_hive.sh), который распаковывает дистрибутивы в домашний каталог пользователя `team`.

Если необходимые каталоги уже существуют, повторная распаковка не выполняется.

### 2. Подготовка PostgreSQL

Сценарий [plan-postgres.yml](../.github/workflows/plan-postgres.yml) выполняет установку и первоначальную настройку PostgreSQL 16 на узле `team-14-00`.

Он проверяет наличие PostgreSQL, при необходимости устанавливает его, настраивает ограничения на использование ресурсов и создает базу данных `hive_metastore` с пользователем `hive`.

База PostgreSQL предназначена для хранения метаданных Hive.

### 3. Настройка Hive Metastore

Основной скрипт [deploy.sh](deploy.sh) содержит проверку окружения и настройку отдельного Hive Metastore.

Metastore работает на узле `team-14-00` и принимает подключения через порт `9083`. Для подключения к PostgreSQL используется JDBC-драйвер, а параметры соединения сохраняются в `hive-site.xml`.

Метаданные Hive хранятся в PostgreSQL, а не в локальной встроенной базе Derby.

### 4. Настройка HiveServer2

HiveServer2 работает на edge-ноде `team-14-en`.

В конфигурации задаются следующие параметры:

- Адрес Metastore – `thrift://team-14-00:9083`.
- Порт HiveServer2 – `10000`.
- Адрес прослушивания – `127.0.0.1`.
- Движок выполнения запросов по умолчанию – Tez.

Для управления сервером используется сценарий [deploy-hive.yml](../.github/workflows/deploy-hive.yml).

В текущей версии сценарий запускает `deploy.sh` с аргументом `--restart-hs2-only`. Этот режим предназначен для настройки и перезапуска HiveServer2 на уже подготовленном кластере без перезапуска HDFS, YARN, PostgreSQL и Metastore.

Первоначальная настройка Metastore предусмотрена основной частью `deploy.sh`. Полное развертывание всей инфраструктуры на пустых серверах одним запуском не проверялось.

## Проверка многопользовательского доступа

Для подключения к HiveServer2 используется Beeline:

```bash
beeline -u "jdbc:hive2://127.0.0.1:10000/default"
```

Для проверки параллельного доступа создан сценарий [check-hiveserver2-log.yml](../.github/workflows/check-hiveserver2-log.yml).

Он одновременно запускает два независимых клиента Beeline. Каждый подключается к HiveServer2 и выполняет команду:

```sql
SHOW DATABASES;
```

После запуска сценарий ожидает завершения обоих процессов и проверяет результат выполнения запросов.

Запуск `Check HiveServer2 Log #14` завершился успешно 22 октября 2026 года. Оба клиента смогли подключиться к одному экземпляру HiveServer2.

Таким образом, подтверждена возможность одновременного использования Hive несколькими клиентами без embedded-режима.

## Подготовка Apache Tez

Для выполнения вычислительных заданий был подготовлен Apache Tez 0.10.5.

Сценарий [setup-tez.yml](../.github/workflows/setup-tez.yml) запускает [setup_tez.sh](setup_tez.sh), который размещает архив Tez в HDFS по пути:

```text
/apps/tez/tez-0.10.5.tar.gz
```

Скрипт создает конфигурационный файл `tez-site.xml` с адресом архива в HDFS.

Дополнительно используется [configure_hive_tez.sh](configure_hive_tez.sh), который подготавливает конфигурацию Tez для Hive.

При попытке выполнения вычислительных запросов через Tez возникла ошибка запуска контейнера YARN. Поэтому для основной задачи загрузки данных был дополнительно реализован способ, не требующий вычислительного движка.

## Автоматизированная загрузка данных

В качестве исходных данных используется файл [transactions.csv](transactions.csv), содержащий 12 записей о транзакциях.

Исходный CSV загружен в HDFS по пути:

```text
/user/team/hw3/raw_transactions/transactions.csv
```

Основной рабочий способ загрузки реализован в сценарии [load-hw3-partitioned-text.yml](../.github/workflows/load-hw3-partitioned-text.yml).

### 1. Подготовка данных

Сценарий считывает исходный CSV из HDFS и разделяет записи по значению `transaction_year`.

В исходном файле содержатся данные за три года:

- 2024 – 4 записи.
- 2025 – 4 записи.
- 2026 – 4 записи.

При обработке удаляется строка заголовка. Поле `transaction_year` используется для определения нужной партиции, а оставшиеся четыре поля записываются в подготовленные файлы.

Для хранения создаются следующие каталоги HDFS:

```text
/user/team/hw3/transactions_partitioned_text/
    transaction_year=2024/
        data.csv
    transaction_year=2025/
        data.csv
    transaction_year=2026/
        data.csv
```

Данные загружаются в соответствующие каталоги с помощью `hdfs dfs -put`.

### 2. Создание партиционированной таблицы

Затем через Beeline создается внешняя таблица `hw3.transactions_partitioned_text`:

```sql
CREATE DATABASE IF NOT EXISTS hw3;

CREATE EXTERNAL TABLE IF NOT EXISTS
hw3.transactions_partitioned_text (
    transaction_id INT,
    customer_id INT,
    amount DOUBLE,
    category STRING
)
PARTITIONED BY (transaction_year INT)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION
'/user/team/hw3/transactions_partitioned_text';
```

Таблица хранит четыре основных поля транзакции. Пятое поле – `transaction_year` – используется как ключ партиционирования.

### 3. Регистрация партиций

После загрузки файлов выполняется SQL-команда:

```sql
ALTER TABLE hw3.transactions_partitioned_text
ADD IF NOT EXISTS
PARTITION (transaction_year=2024)
PARTITION (transaction_year=2025)
PARTITION (transaction_year=2026);
```

Эта команда регистрирует три существующих каталога как партиции таблицы Hive.

В данном подходе данные предварительно распределяются по каталогам HDFS, поэтому для самой загрузки и регистрации партиций не требуется выполнение MapReduce или Tez.

Сценарий не изменяет исходный CSV, конфигурации серверов и ранее созданную таблицу `hw3.transactions`.

## Проверка результатов загрузки

Для проверки используются команды:

```sql
SHOW PARTITIONS hw3.transactions_partitioned_text;

SELECT *
FROM hw3.transactions_partitioned_text
LIMIT 20;
```

Сценарий `Load HW3 Partitioned Text #1` успешно завершился 22 октября 2026 года.

В результате `SHOW PARTITIONS` получены три партиции:

```text
transaction_year=2024
transaction_year=2025
transaction_year=2026
```

Запрос `SELECT *` вернул все 12 записей с корректными значениями полей и годами транзакций.

Результаты распределения записей:

| Год | Количество записей |
|---|---:|
| 2024 | 4 |
| 2025 | 4 |
| 2026 | 4 |
| Всего | 12 |

Также подтверждено наличие трех файлов `data.csv` в соответствующих каталогах HDFS.

Таким образом, автоматизированная загрузка данных в партиционированную таблицу Hive выполнена и проверена.

## Дополнительный вариант загрузки через Parquet

Помимо основного рабочего способа, в репозитории сохранены файлы [create_table.sql](create_table.sql), [load_data.sql](load_data.sql) и [load_data.sh](load_data.sh).

Первый SQL-файл создает таблицу `hw3.transactions` в формате Parquet с партиционированием по `transaction_year`. Второй читает исходный CSV через промежуточную таблицу `transactions_raw` и предусматривает запись данных командой:

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

Автоматизированный запуск этого способа предусмотрен в [load-hive-data.yml](../.github/workflows/load-hive-data.yml).

При выполнении возникли ошибки вычислительных заданий YARN:

1. Для Tez – `ClassNotFoundException: org.apache.tez.dag.app.DAGAppMaster`.
2. Для MapReduce – ошибка выполнения задания после его отправки в YARN.

Поэтому заполнение таблицы Parquet не было успешно завершено.

Для выполнения основной задачи выбран альтернативный способ с текстовой партиционированной таблицей. Он успешно прошел проверку и не требует исправления вычислительных движков.

## Запуск через GitHub Actions

Все сценарии находятся в каталоге `.github/workflows/` и запускаются вручную через `workflow_dispatch`.

Для запуска необходимо открыть вкладку **Actions** в репозитории, выбрать нужный сценарий, нажать **Run workflow** и выбрать ветку `master`.

Основные сценарии домашнего задания №3:

1. [prepare-hive.yml](../.github/workflows/prepare-hive.yml) – скачивание архивов Hive и Tez.
2. [unpack-hive.yml](../.github/workflows/unpack-hive.yml) – распаковка дистрибутивов.
3. [plan-postgres.yml](../.github/workflows/plan-postgres.yml) – установка и подготовка PostgreSQL.
4. [deploy-hive.yml](../.github/workflows/deploy-hive.yml) – настройка и перезапуск HiveServer2 на подготовленном кластере.
5. [setup-tez.yml](../.github/workflows/setup-tez.yml) – настройка Tez и загрузка исходного CSV в HDFS.
6. [check-hiveserver2-log.yml](../.github/workflows/check-hiveserver2-log.yml) – проверка двух одновременных клиентов.
7. [load-hw3-partitioned-text.yml](../.github/workflows/load-hw3-partitioned-text.yml) – успешная загрузка данных в текстовую партиционированную таблицу.
8. [load-hive-data.yml](../.github/workflows/load-hive-data.yml) – дополнительный вариант загрузки в Parquet, выполнение которого не завершилось успешно.

Дополнительно предусмотрен сценарий [check-hw3-readiness.yml](../.github/workflows/check-hw3-readiness.yml), который проверяет доступность HiveServer2 и исходного CSV в HDFS без изменения конфигурации кластера.

Для работы необходимы предварительно подготовленные HDFS и YARN, доступ между узлами и настроенная база Metastore. Сценарий `deploy-hive.yml` в текущем режиме не выполняет полную первоначальную установку с нуля.

Для подключения используются GitHub Secrets:

- `SSH_PRIVATE` – приватный SSH-ключ для подключения к edge-ноде.
- `KNOWN_HOSTS` – проверенная запись SSH-хоста.
- `HIVE_DB_PASSWORD` – пароль пользователя PostgreSQL для Hive.

Секреты не хранятся в открытых файлах репозитория.

В репозитории также сохранены сценарии `deploy-hdfs.yml` и `deploy-yarn.yml`, относящиеся к предыдущим домашним заданиям.

## Итог

В работе развернут Apache Hive 4.1.0 с отдельным Hive Metastore на PostgreSQL и HiveServer2. Embedded-режим не используется.
Успешно проверена возможность одновременного подключения двух независимых клиентов Beeline.
Реализована автоматизированная загрузка 12 записей из CSV в текстовую партиционированную таблицу Hive. Данные распределены по трем партициям – 2024, 2025 и 2026 годы. Наличие партиций и корректность чтения записей подтверждены результатами SQL-запросов.

Первоначальный вариант загрузки в Parquet не удалось завершить из-за ошибок выполнения вычислительных заданий. Однако основной способ загрузки в TEXTFILE успешно выполнен и позволяет удовлетворить требование задания о партиционированной таблице Hive.
Полное развертывание инфраструктуры на пустом кластере одним запуском не проверялось; инструкция и скрипты рассчитаны на подготовленное окружение Hadoop.
