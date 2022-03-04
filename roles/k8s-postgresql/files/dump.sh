#!/bin/bash
set -e
IFS=$'\n\t'

Q_LIST_DATABASES="SELECT datname FROM pg_database WHERE datname NOT LIKE 'template%'"
DATE_FORMAT="%Y%m%dT%H%M%S"
RETENTION_DAYS="7"
DUMP_EXTENSION="dump"

dump() {
  ctime=$(date "+${DATE_FORMAT}")
  databases=$(psql -Atqd postgres -c "${Q_LIST_DATABASES}")
  for db in ${databases}; do
    echo "[*] dumping database ${db}"
    path="${TARGET_PATH}/${db}-${ctime}.${DUMP_EXTENSION}"
    pg_dump -vcC -Fc -Z9 -d "${db}" -f "${path}"
  done
}

cleanup() {
  find "${TARGET_PATH}" -maxdepth 1 -name "*.${DUMP_EXTENSION}" -ctime "+${RETENTION_DAYS}"
}

cleanup
dump
