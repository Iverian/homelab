HERE=$(readlink -f $(dirname -- "${0}"))
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

export ANSIBLE_ROOT="${HERE}"
export ANSIBLE_CONFIG="${HERE}/ansible.cfg"
export ANSIBLE_ROLES_PATH="${HERE}/roles:${HERE}/3d/kubespray/roles"
export ANSIBLE_LIBRARY="${HERE}/library:${HERE}/3d/kubespray/library"
export ANSIBLE_CACHE_PLUGIN_CONNECTION="${HERE}/.cache"
export ANSIBLE_VAULT_PASSWORD_FILE="${HERE}/.vault-pass"

install() {
  if [ ! -d "${VENV_DIR}" ]; then
    pipenv --python 3
  fi
  pipenv install
  pipenv run ansible-galaxy collection install -f -r "${REQUIREMENTS_FILE}"
  pipenv run ansible-galaxy role install -f -r "${REQUIREMENTS_FILE}"
}

if [ "$#" -eq 0 ]; then
  mkdir -p "${ANSIBLE_CACHE_PLUGIN_CONNECTION}"
  . "${VENV_DIR}/bin/activate"
else
  arg="$1"
  case ${arg} in
  help)
    echo "${USAGE}"
    ;;
  install)
    install
    ;;
  *)
    echo -e "Invalid argument ${arg}\n${USAGE}"
    ;;
  esac
fi
