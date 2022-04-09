#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

BACKUP_TEMP_PATH="${BACKUP_TEMP_PATH}"
BACKUP_TARGET_PATH="${BACKUP_TARGET_PATH}"

Q_LIST_DATABASES="SELECT datname FROM pg_database WHERE datname NOT LIKE 'template%'"
DATE_FORMAT="%Y%m%dT%H%M%S"
DUMP_EXTENSION="dump"
COMPRESS_LEVEL="3"
JOBS="2"

cleanup() {
  rm -rf ${BACKUP_TEMP_PATH}/*
}

main() {
  ctime=$(date "+${DATE_FORMAT}")
  cd "${BACKUP_TEMP_PATH}"
  for db in $(psql -Atqd postgres -c "${Q_LIST_DATABASES}"); do
    echo "[*] dumping database ${db}"
    backup_name="${db}-${ctime}.${DUMP_EXTENSION}"
    temp_path="${BACKUP_TEMP_PATH}/${backup_name}"
    target_path="${BACKUP_TARGET_PATH}/${backup_name}.tar.gz"

    pg_dump --verbose --clean --format d --dbname "${db}" --file "${temp_path}" --jobs "${JOBS}" --compress "${COMPRESS_LEVEL}" || return $?
    tar --create --file "${target_path}" "${backup_name}" || return $?
  done
  return 0
}

trap cleanup EXIT
main || exit $?
