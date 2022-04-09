FILE=$([ -f "${BASH_SOURCE}" ] && echo "${BASH_SOURCE}" || echo "${0}")
FILE=$(readlink -f "${FILE}")

HERE=$(readlink -f $(dirname -- "${FILE}"))
VENV_DIR="${HERE}/.venv"
REQUIREMENTS_FILE="${HERE}/requirements.yaml"
USAGE="USAGE: . activate.sh [help|install]
Activate Ansible Environenment

SUBCOMMANDS:
  help: show this message
  install: install requirements
"

export PIPENV_VENV_IN_PROJECT="1"
export PIPENV_VERBOSITY="-1"

log_info() {
  echo "[*] $@"
}

log_error() {
  echo "[x] $@"
}

install() {
  if [ ! -d "${VENV_DIR}" ]; then
    log_info "creating virtualenv at '${VENV_DIR}'"
    pipenv --python 3 || return $?
  fi

  log_info "installing python dependencies"
  pipenv install || return $?
  log_info "installing ansible collections"
  pipenv run ansible-galaxy collection install -f -r "${REQUIREMENTS_FILE}" || return $?
  log_info "installing ansible roles"
  pipenv run ansible-galaxy role install -f -r "${REQUIREMENTS_FILE}" || return $?

  return 0
}

activate_env() {
  if [ ! -d "${VENV_DIR}" ]; then
    log_error "virtualenv directory does not exist, install dependencies first with '. activate.sh install'"
    return 1
  fi

  export ANSIBLE_ROOT="${HERE}"
  export ANSIBLE_CONFIG="${HERE}/ansible.cfg"
  export ANSIBLE_ROLES_PATH="${HERE}/roles:${HERE}/3d/kubespray/roles"
  export ANSIBLE_LIBRARY="${HERE}/library:${HERE}/3d/kubespray/library"
  export ANSIBLE_CACHE_PLUGIN_CONNECTION="${HERE}/.cache"
  export ANSIBLE_VAULT_PASSWORD_FILE="${HERE}/.vault-pass"

  mkdir -p "${ANSIBLE_CACHE_PLUGIN_CONNECTION}"
  . "${VENV_DIR}/bin/activate"

  return 0
}

main() {
  if [ "$#" -eq 0 ]; then
    activate_env || return $?
    return 0
  fi

  command="$1"
  case ${command} in
  "help")
    echo "${USAGE}"
    ;;
  "install")
    install || return $?
    ;;
  *)
    log_error "invalid command ${command}
${USAGE}"
    ;;
  esac
}

main "$@"
