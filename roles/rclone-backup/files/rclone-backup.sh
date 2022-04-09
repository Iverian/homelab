#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

RCLONE_CONFIG="${RCLONE_CONFIG}"
RCLONE_REMOTE="${RCLONE_REMOTE}"
RCLONE_BACKUP_PATH="${RCLONE_BACKUP_PATH}"
RCLONE_RETENTION_DAYS="${RCLONE_RETENTION_DAYS}"

main() {
    rm -f $(find "${RCLONE_BACKUP_PATH}" -type f -ctime "+${RCLONE_RETENTION_DAYS}") || return $?
    rclone --verbose --config="${RCLONE_CONFIG}" sync "${RCLONE_BACKUP_PATH}" "${RCLONE_REMOTE}" || return $?
    return 0
}

main || exit $?
