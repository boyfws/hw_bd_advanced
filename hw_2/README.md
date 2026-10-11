# Автоматизированное развертывание YARN

В этой работе автоматически разворачивается Hadoop и YARN на четырех узлах. Развертывание запускается вручную через GitHub Actions. Workflow отвечает за подключение к edge-ноде и передачу скрипта, [deploy.sh](./deploy.sh) выполняется уже на edge-ноде и настраивает HDFS и YARN.

## Состав кластера

Рассмотрим каждый узел, его адрес и что на нем хостится:

1. `team-14-nn`, `10.14.0.11`: NameNode, Secondary NameNode, ResourceManager и JobHistoryServer
2. `team-14-en`, `10.14.0.10`: edge-нода, DataNode и NodeManager
3. `team-14-00`, `10.14.0.12`: DataNode и NodeManager
4. `team-14-01`, `10.14.0.13`: DataNode и NodeManager

## Как устроено развертывание

Файл [`.github/workflows/deploy-yarn.yml`](../.github/workflows/deploy-yarn.yml) запускается вручную (`workflow_dispatch`) через GitHub Actions.

Что делает workflow:

1. Получает выбранную для запуска ветку репозитория.
2. Проверяет синтаксис `hw_2/deploy.sh` командой `bash -n`.
3. Записывает GitHub Secrets в `.ssh` на runner и проверяет, что OpenSSH может прочитать приватный ключ.
4. Копирует `hw_2/deploy.sh` на `team@171.22.72.225` под именем `yarn-deploy.sh` и запускает его там через `bash`.
5. После деплоя создает временный SSH-туннель из runner к веб-интерфейсам Hadoop и выполняет HTTP-проверки. Туннель закрывается при завершении шага. В целом, этот шаг необходим для проверки доступности web-интерфейсов


## Что делает deploy.sh

Скрипт выполняет следующие действия:

1. Проверяет, что он запущен на `team-14-en` от пользователя `team`, что доступен внутренний SSH-ключ, а узлы доступны и соответствуют требованиям по ОС, архитектуре и ресурсам.
2. Устанавливает java и необходимые программы и утилиты, создает каталоги для hdfs и проверяет жизнеспособность hadoop.
3. Записывает конфигурации yarn и mapreduce на все узлы.
4. Запускает resource manager и job history server на `team-14-nn`, а node managre - на 3 узлах с datanode.
5. Ожидает регистрации трех node managers в resource manager и проверяет, что все они имеют состояние `running`.

## Настройка YARN

Yarn конфиг записывается в `yarn-site.xml` на всех узлах. RM находится на `team-14-nn`, NMs работают на узлах `team-14-en`, `team-14-00` и `team-14-01`.

```bash
YARN_RM="$NAMENODE"
JOB_HISTORY_SERVER="$NAMENODE"
NODEMANAGERS=("${DATANODES[@]}")
```

В `yarn-site.xml` скрипт указывает адрес RM, включает вспомогательную службу shuffle для mapreduce и задает ресурсы NM:

```xml
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
    <name>yarn.nodemanager.resource.memory-mb</name>
    <value>1024</value>
</property>
<property>
    <name>yarn.nodemanager.resource.cpu-vcores</name>
    <value>1</value>
</property>
```

На каждом NodeManager для контейнеров выделяется до `1024 MiB` и `1 vCore`. Привязка `0.0.0.0` нужна по аналогичной причине из дз-1: чтобы слушать запросы.

## Настройка mapreduce и истории заданий

Файл `mapred-site.xml` также создается на всех узлах:

```xml
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
```

`mapreduce.framework.name=yarn` указывает mapreduce использовать yarn. history server принимает служебные запросы по порту `10020` и предоставляет веб-интерфейс истории завершенных заданий на порту `19888`. Он запускается отдельно от RM/NM.

## Запуск демонов и проверка

Общий скрипт запускается один раз на edge-ноде, а нужные демоны он адресно запускает на выбранных узлах:

```bash
restart_yarn_daemon "$YARN_RM" "yarn" "resourcemanager"
restart_yarn_daemon "$JOB_HISTORY_SERVER" "mapred" "historyserver"

for node in "${NODEMANAGERS[@]}"; do
    restart_yarn_daemon "$node" "yarn" "nodemanager"
done
```

После запуска RM опрашивается командой `yarn node -list -all`. Скрипт ждет, пока число узлов в состоянии `RUNNING` совпадет с количеством NMs в массиве `NODEMANAGERS`:

```bash
resultik="$(
    printf '%s\n' "$yarn_nodes" |
        awk '$2 == "RUNNING" { count++ } END { print count + 0 }'
)"

if [[ "$resultik" -ne "${#NODEMANAGERS[@]}" ]]; then
    echo "не все nodemanagers сообщили о себе в rm" >&2
    exit 1
fi
```
Эта проверка подтверждает, что RM видит три работающих NMs.

## Настройка GitHub Actions

В настройках репозитория в GitHub Actions должны быть заданы Secrets:

1. `SSH_PRIVATE`: приватный SSH-ключ, которым runner подключается к edge-ноде как `team`. Workflow записывает его во временный файл на runner и проверяет через `ssh-keygen`.
2. `KNOWN_HOSTS`: проверенная запись `known_hosts` для edge-ноды `171.22.72.225`.


## Запуск

1. Убедитесь, что заданы secrets `SSH_PRIVATE` и `KNOWN_HOSTS`
2. В репозитории перейдите на вкладку `Actions` и выберите workflow `autodeploy-yarn`.
3. Нажмите `Run workflow`, выберите ветку `master` и запустите.
4. Дальше только следить за логами и ждать результата

Повторный запуск перезапускает службы и сохраняет существующие каталоги хадупа.

## Проверка веб-интерфейсов

После деплоя workflow создает SSH-туннель внутри runner и проверяет HTTP-ответы по следующим адресам:

Формат служба - узел - порт:
1. namenode ui - `team-14-nn` - `9870` 
2. secondarynamenode  ui - `team-14-nn` - `9868` 
3. resourcemanager ui  - `team-14-nn` - `8088` 
4. jobhistoryserver ui  - `team-14-nn` - `19888` 
5. datanode ui  - `team-14-en` - `team-14-00`, `team-14-01` - `9864` 
6. nodemanager ui  - `team-14-en`-`team-14-00` -`team-14-01` - `8042` 

Проверка через туннель подтверждает http-доступность интерфейсов. После завершения action туннель выключается. То есть, пингануть изнутри запуска можно, но вот получить наружний доступ через url или что-то подобное не получится. В логах должна выводиться отладка что все службы пингуются и с ними все хорошо, это можно увидеть в логах.