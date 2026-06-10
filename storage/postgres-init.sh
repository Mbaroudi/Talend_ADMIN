#!/bin/sh
# Creates the dedicated Rundeck database inside the same PostgreSQL instance.
# Runs once, on first cluster initialisation.
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE "${RUNDECK_DB_NAME}" OWNER "${POSTGRES_USER}";
EOSQL

echo "Created Rundeck database: ${RUNDECK_DB_NAME}"
