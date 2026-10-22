# Автоматизированное развертывание Apache Hive

В этой работе выполняется развертывание Apache Hive с возможностью одновременного подключения нескольких клиентов. Для хранения метаданных используется отдельный Hive Metastore с PostgreSQL, а для подключения клиентов – HiveServer2. Таким образом, embedded-режим не используется.

Также реализована автоматизированная загрузка данных из CSV-файла в партиционированную таблицу Hive. Для подготовки компонентов, настройки служб и загрузки данных используются GitHub Actions.

## Состав кластера

Для выполнения задания используется кластер Hadoop, развернутый в предыдущих домашних работах.

1. `team-14-nn`, `10.14.0.11` - NameNode, Secondary NameNode, ResourceManager и JobHistoryServer.
2. `team-14-en`, `10.14.0.10` - edge-нода, DataNode, NodeManager и HiveServer2.
3. `team-14-00`, `10.14.0.12` - DataNode, NodeManager, Hive Metastore и PostgreSQL.
4. `team-14-01`, `10.14.0.13` – DataNode и NodeManager.

Используются Apache Hadoop 3.5.0, Apache Hive 4.1.0 и PostgreSQL 16.

Hadoop установлен в `$HOME/hadoop-3.5.0`, Hive - в `$HOME/apache-hive-4.1.0-bin`.

Вместо рекомендованной версии Hive 4.0.0-alpha2 используется версия 4.1.0.

## Как устроено развертывание

Развертывание разделено на несколько этапов. GitHub Actions подключается к edge-ноде по SSH, передает необходимые скрипты и запускает их на сервере.

Предварительно должен быть настроен Hadoop-кластер с работающими HDFS и YARN.

### 1. Подготовка дистрибутивов

Сценарий [prepare-hive.yml](../.github/workflows/prepare-hive.yml) запускает скрипт [prepare_hive.sh](prepare_hive.sh).

Он загружает необходимые архивы в `$HOME/hw3-downloads` и проверяет их доступность и целостность с помощью `tar`.

Затем сценарий [unpack-hive.yml](../.github/workflows/unpack-hive.yml) запускает [unpack_hive.sh](unpack_hive.sh), который распаковывает компоненты в домашний каталог пользователя `team`.

Если соответствующие каталоги уже существуют, повторная распаковка не выполняется.

### 2. Подготовка PostgreSQL

Сценарий [plan-postgres.yml](../.github/workflows/plan-postgres.yml) устанавливает и настраивает PostgreSQL 16 на узле `team-14-00`.

Он проверяет наличие PostgreSQL, при необходимости устанавливает его, задает ограничения на использование ресурсов, создает базу данных `hive_metastore` и пользователя `hive`.

PostgreSQL используется Hive Metastore для хранения информации о базах данных, таблицах и партициях.

### 3. Настройка Hive Metastore

Основной скрипт [deploy.sh](deploy.sh) содержит команды настройки отдельного Hive Metastore.

Metastore располагается на узле `team-14-00` и принимает подключения через порт `9083`.

Для подключения к PostgreSQL используется JDBC-драйвер. Конфигурация сохраняется в файле `hive-site.xml`.

Поскольку метаданные хранятся в отдельной базе PostgreSQL, локальная встроенная база Derby не используется.

### 4. Настройка HiveServer2

HiveServer2 работает на edge-ноде `team-14-en` и принимает подключения клиентов через порт `10000`.

Основные параметры конфигурации:

- Адрес Metastore – `thrift://team-14-00:9083`.
- Порт HiveServer2 – `10000`.
- Адрес прослушивания – `127.0.0.1`.
- Доступ к Metastore – через отдельную службу.

Для настройки и запуска HiveServer2 используется [deploy-hive.yml](../.github/workflows/deploy-hive.yml).

В текущей конфигурации сценарий вызывает `deploy.sh` с аргументом `--restart-hs2-only`. Этот режим предназначен для уже подготовленного окружения и позволяет настраивать и перезапускать HiveServer2 без перезапуска HDFS, YARN и PostgreSQL.

Первоначальная настройка Metastore предусмотрена основной частью `deploy.sh`.

## Проверка многопользовательского доступа

Для подключения к HiveServer2 используется Beeline:

```bash
beeline -u "jdbc:hive2://127.0.0.1:10000/default"
```

Для проверки одновременного подключения нескольких клиентов подготовлен сценарий [check-hiveserver2-log.yml](../.github/workflows/check-hiveserver2-log.yml).

Сценарий параллельно запускает два независимых клиента Beeline. Каждый подключается к HiveServer2 и выполняет запрос:

```sql
SHOW DATABASES;
```

После этого сценарий ожидает завершения обоих процессов и проверяет результат выполнения команд.

22 октября 2026 года проверка `Check HiveServer2 Log #14` завершилась успешно.

Оба клиента смогли подключиться к одному экземпляру HiveServer2 и выполнить SQL-запросы.

Таким образом, подтверждена возможность многопользовательского доступа к Hive без embedded-режима.

## Автоматизированная загрузка данных

В качестве исходных данных используется файл [transactions.csv](transactions.csv), содержащий 12 записей о транзакциях.

Исходный файл размещен в HDFS по пути:

```text
/user/team/hw3/raw_transactions/transactions.csv
```

Для автоматизированной загрузки подготовлен сценарий [load-hw3-partitioned-text.yml](../.github/workflows/load-hw3-partitioned-text.yml), который выполняет подготовку данных, создание таблицы и проверку результата.

### 1. Подготовка данных

Сценарий считывает исходный CSV из HDFS и разделяет записи по значению `transaction_year`.

Исходные данные содержат транзакции за три года:

1. 2024 – 4 записи.
2. 2025 – 4 записи.
3. 2026 – 4 записи.

При подготовке удаляется заголовок CSV. Поле `transaction_year` используется для распределения записей, а остальные четыре поля сохраняются в отдельных файлах для каждого года.

В HDFS создаются следующие каталоги:

```text
/user/team/hw3/transactions_partitioned_text/
    transaction_year=2024/
        data.csv
    transaction_year=2025/
        data.csv
    transaction_year=2026/
        data.csv
```

Для загрузки подготовленных файлов используется команда `hdfs dfs -put`.

### 2. Создание партиционированной таблицы

После размещения файлов через Beeline создается внешняя таблица `hw3.transactions_partitioned_text`:

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

Таблица содержит четыре основных поля транзакции:

1. `transaction_id` – идентификатор транзакции.
2. `customer_id` – идентификатор клиента.
3. `amount` – сумма транзакции.
4. `category` – категория транзакции.

Поле `transaction_year` используется как ключ партиционирования.

### 3. Регистрация партиций

После загрузки данных сценарий регистрирует партиции в Hive:

```sql
ALTER TABLE hw3.transactions_partitioned_text
ADD IF NOT EXISTS
PARTITION (transaction_year=2024)
PARTITION (transaction_year=2025)
PARTITION (transaction_year=2026);
```

Каждая партиция соответствует отдельному каталогу HDFS.

Данные распределяются по каталогам до регистрации партиций, поэтому для этого процесса не требуется выполнение дополнительных вычислительных заданий.

Сценарий не изменяет исходный CSV и существующие таблицы.

## Проверка результатов загрузки

После загрузки выполняются запросы:

```sql
SHOW PARTITIONS hw3.transactions_partitioned_text;

SELECT *
FROM hw3.transactions_partitioned_text
LIMIT 20;
```

Сценарий `Load HW3 Partitioned Text #1` успешно завершился

Запрос `SHOW PARTITIONS` вернул три партиции:

```text
transaction_year=2024
transaction_year=2025
transaction_year=2026
```

Запрос `SELECT *` вернул все 12 записей с корректными значениями полей.

Распределение записей по партициям:

| Год | Количество записей |
|---|---:|
| 2024 | 4 |
| 2025 | 4 |
| 2026 | 4 |
| **Всего** | **12** |

Дополнительно проверено наличие файлов `data.csv` в каждой из трех партиций HDFS.

Таким образом, автоматизированная загрузка данных в партиционированную таблицу Hive выполнена и подтверждена результатами запросов.

## Дополнительные файлы проекта

В каталоге `hw_3` также представлены:

- [create_table.sql](create_table.sql) – создание дополнительной партиционированной таблицы в формате Parquet.
- [load_data.sql](load_data.sql) – SQL-команды чтения исходного CSV и переноса данных.
- [load_data.sh](load_data.sh) – отдельный скрипт подготовки данных и выполнения SQL-команд.
- [setup_tez.sh](setup_tez.sh) – подготовка дополнительного компонента выполнения запросов.
- [configure_hive_tez.sh](configure_hive_tez.sh) – настройка взаимодействия Hive с дополнительным компонентом.

Основной проверенный способ автоматизированной загрузки находится в `load-hw3-partitioned-text.yml`.

## Запуск через GitHub Actions

Все сценарии находятся в каталоге `.github/workflows/`.

Для запуска необходимо открыть вкладку **Actions** в репозитории, выбрать нужный сценарий, нажать **Run workflow** и выбрать ветку `master`.

Основные сценарии домашнего задания:

1. [prepare-hive.yml](../.github/workflows/prepare-hive.yml) – подготовка архивов.
2. [unpack-hive.yml](../.github/workflows/unpack-hive.yml) – распаковка компонентов.
3. [plan-postgres.yml](../.github/workflows/plan-postgres.yml) – установка и настройка PostgreSQL.
4. [deploy-hive.yml](../.github/workflows/deploy-hive.yml) – настройка и перезапуск HiveServer2.
5. [setup-tez.yml](../.github/workflows/setup-tez.yml) – подготовка дополнительного компонента и загрузка исходного CSV в HDFS.
6. [check-hiveserver2-log.yml](../.github/workflows/check-hiveserver2-log.yml) – проверка параллельных подключений клиентов.
7. [load-hw3-partitioned-text.yml](../.github/workflows/load-hw3-partitioned-text.yml) – автоматизированная загрузка данных в партиционированную таблицу.
8. [load-hive-data.yml](../.github/workflows/load-hive-data.yml) – дополнительный сценарий загрузки в формате Parquet.

Для предварительной проверки состояния HDFS и HiveServer2 предусмотрен [check-hw3-readiness.yml](../.github/workflows/check-hw3-readiness.yml).

Для запуска используются GitHub Secrets:

- `SSH_PRIVATE` – приватный SSH-ключ для подключения к edge-ноде.
- `KNOWN_HOSTS` – сведения о доверенном SSH-хосте.
- `HIVE_DB_PASSWORD` – пароль пользователя PostgreSQL.

Значения секретов не хранятся в открытом коде.

В репозитории также находятся сценарии `deploy-hdfs.yml` и `deploy-yarn.yml`, относящиеся к предыдущим домашним заданиям.

Для выполнения задания необходимо подготовленное окружение Hadoop, доступ между узлами и настроенная база метаданных Hive. Полная установка на пустых серверах одним запуском не проверялась.

## Итог

В работе развернут Apache Hive 4.1.0 с отдельным Hive Metastore, использующим PostgreSQL, и сервером HiveServer2. Embedded-режим не используется.
Успешно проверено одновременное подключение двух независимых клиентов Beeline к HiveServer2.
Также реализована и проверена автоматизированная загрузка 12 записей из CSV в партиционированную таблицу `hw3.transactions_partitioned_text`. Данные распределены по трем партициям – 2024, 2025 и 2026 годы. Наличие партиций и корректность чтения всех записей подтверждены результатами SQL-запросов.

Таким образом, реализованы оба основных требования задания – многопользовательский доступ к Apache Hive и автоматизированная загрузка данных в партиционированную таблицу.
