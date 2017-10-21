#!/bin/bash -e

SETUP_SQL="
CREATE DATABASE airflow;
CREATE USER 'airflow'@'localhost' IDENTIFIED BY 'airflow';
GRANT ALL PRIVILEGES ON 'airflow.*' TO airflow;
"

mysql -u root -proot --execute="$SETUP_SQL"

airflow initdb
