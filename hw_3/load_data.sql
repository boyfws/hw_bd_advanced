SET tez.lib.uris.classpath=./apache-tez-0.10.5-bin/*:./apache-tez-0.10.5-bin/lib/*;
USE hw3;

CREATE EXTERNAL TABLE IF NOT EXISTS transactions_raw (
    transaction_id INT,
    customer_id INT,
    amount DOUBLE,
    category STRING,
    transaction_year INT
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/user/team/hw3/raw_transactions'
TBLPROPERTIES ('skip.header.line.count'='1');

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
