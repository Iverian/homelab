#!/usr/bin/env zsh

HERE=$(readlink -f $(dirname -- "${0}"))
VENV_DIR="${HERE}/.venv"

export PIPENV_VENV_IN_PROJECT="1"
export PIPENV_VERBOSITY="-1"
export ANSIBLE_CONFIG="${HERE}/ansible.cfg"

install() {
    if [ ! -d "${VENV_DIR}" ]; then
        pipenv --python 3
    fi
    pipenv install
    pipenv run ansible-galaxy collection install -f -r "$HERE/requirements.yaml"
    pipenv run ansible-galaxy role install -f -r "$HERE/requirements.yaml"
}

[ "$#" -eq "0" ] && install || true

echo "root = ${HERE}"
env ANSIBLE_ROOT="${HERE}" pipenv shell
