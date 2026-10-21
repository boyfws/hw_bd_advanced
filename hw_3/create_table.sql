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