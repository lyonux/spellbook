#!/usr/bin/env bash

set -x
set -e
set -o pipefail

ROOT_DIR="$(dirname "${BASH_SOURCE[0]}")"
KUBE_DIR="${ROOT_DIR}/.kube"
VENV_DIR="${ROOT_DIR}/.venv"
VENV_ACTIVATE_MITOGEN=$(cat <<EOF
ANSIBLE_STRATEGY="mitogen_linear"
ANSIBLE_STRATEGY_PLUGINS="\$(python -c 'print(__import__("pkg_resources").resource_filename("ansible_mitogen", "plugins/strategy"))')"
if [ -d "\${ANSIBLE_STRATEGY_PLUGINS}" ]; then
  export ANSIBLE_STRATEGY
  export ANSIBLE_STRATEGY_PLUGINS
fi

export PATH="$(cd "${ROOT_DIR}" && pwd)/tools:\$PATH"

KUBECONFIG_VAGRANT="$(cd "${ROOT_DIR}" && pwd)/.kube/config"
if [ -f "\$KUBECONFIG_VAGRANT" ]; then
  export KUBECONFIG="\$KUBECONFIG_VAGRANT"

  # https://github.com/jonmosco/kube-ps1
  KUBE_PS1_ENABLED=1

  # https://github.com/denysdovhan/spaceship-prompt
  SPACESHIP_KUBECTL_SHOW=1
fi
EOF
)

if [ -z "$PIP_INDEX_URL" ]; then
  export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple/
fi

submodule_init() {
  if [ ! -d "${ROOT_DIR}/.git/modules/community" ] || [ "$1" == "always" ]; then
    "${ROOT_DIR}/community/update.sh"
  fi
}

# Ensure uv is installed
ensure_uv() {
  if ! command -v uv &> /dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="${HOME}/.local/bin:${PATH}"
  fi
}

venv_prepare() {
  ensure_uv
  if [ ! -d "${VENV_DIR}" ]; then
    uv venv "${VENV_DIR}"
  fi
  printf '%s\n' "$VENV_ACTIVATE_MITOGEN" > "${VENV_DIR}/bin/activate-mitogen"
}

venv_install() {
  # uv sync handles dependencies automatically using uv.lock
  uv sync --index-url https://pypi.tuna.tsinghua.edu.cn/simple/
}

venv_activate() {
  if [ -z "$CI" ] && [ -z "$VIRTUAL_ENV" ]; then
    venv_prepare
    venv_install
    # shellcheck source=/dev/null
    . "${VENV_DIR}/bin/activate"
    # shellcheck source=/dev/null
    . "${VENV_DIR}/bin/activate-mitogen"
  fi
}

venv_spawn() {
  # Inspired by https://superuser.com/a/591440
  dotdir="$(mktemp -d)"
  cat > "${dotdir}/.zshrc" <<EOF
case "\$(basename "\$SHELL")" in
  zsh)
    export ZDOTDIR="\$OLD_ZDOTDIR"
    if [ -f "\$ZDOTDIR/.zshenv" ]; then
      . "\$ZDOTDIR/.zshenv"
    fi
    if [ -f "\$ZDOTDIR/.zshrc" ]; then
      . "\$ZDOTDIR/.zshrc"
    fi
    ;;
  bash)
    if [ -f ~/.bashrc ]; then
      . ~/.bashrc
    fi
    if [ -f /etc/bash.bashrc ]; then
      . /etc/bash.bashrc
    fi
    ;;
esac

printf >&2 '\\nYou have entered the virtualenv now.\\n'
printf >&2 'Use CTRL-D or "exit" to quit.\\n'
. "${VENV_DIR}/bin/activate"
. "${VENV_DIR}/bin/activate-mitogen"
EOF
  ln -s "${dotdir}/.zshrc" "${dotdir}/.bashrc"
  case $(basename "${SHELL}") in
    zsh)
      export OLD_ZDOTDIR="${ZDOTDIR:-${HOME}}"
      export ZDOTDIR="${dotdir}"
      exec zsh -i
      ;;
    bash)
      exec bash --init-file "${dotdir}/.bashrc" -i
      ;;
    *)
      printf >&2 'Unrecognized shell %s\n' "${SHELL}"
      ;;
  esac
}

install_spellbook() {
  ansible-galaxy install -r ${ROOT_DIR}/requirements.yml -p community --force;
}

case "$1" in
  submodule_update)
    submodule_init always
    ;;
esac

case "$1" in
  up)
    exec "$0" vm up "${@:2}" --provision
    ;;
  st)
    exec "$0" vm status
    ;;
  down)
    exec "$0" vm suspend "${@:2}"
    ;;
  reload)
    exec "$0" vm reload "${@:2}" --provision
    ;;
  rm)
    exec "$0" vm destroy "${@:2}"
    ;;
  sandbox)
    if ! "$0" vm sandbox "${@:2}"; then
      printf >&2 'Please install sandbox plugin:\n\n  %s\n' \
        'vagrant plugin install sahara2'
      exit 2
    fi
    ;;
  snapshot)
    exec "$0" vm snapshot "${@:2}"
    ;;
  helm)
    if [ -d "./charts/$2" ];then
      printf './charts/%s exists\n' "$2"
      return
    fi
    helm create "./charts/$2"
    ;;
  lint)
    $0 lint-helm
    $0 lint-ansible
    $0 lint-yaml
    $0 lint-python
    $0 lint-inventory
    ;;
  lint-helm)
    exec find ./charts -type d -maxdepth 1 -mindepth 1 -exec helm lint {} \+
    ;;
  lint-ansible)
    venv_activate
    exec ansible-lint ./site.yml ./playbooks/*.yml ./inventories/*/*/*.yml
    ;;
  lint-inventory)
    venv_activate
    exit_code=0
    export ANSIBLE_INVENTORY_ENABLED="ini"
    for inventory in inventories/*/hosts; do
      warn="$(ansible-inventory -i "$inventory" --list all 2>&1 1>/dev/null)"
      if [ -n "$warn" ]; then
        printf '== Incomplete inventory: %s ==\n%s\n\n' "$inventory" "$warn"
        exit_code="1"
      fi
    done
    exit "$exit_code"
    ;;
  lint-yaml)
    venv_activate
    exec yamllint .
    ;;
  lint-python)
    venv_activate
    exec flake8 .
    ;;
  test-python)
    venv_activate
    ./tools/fetch-inventory none --test
    find ./plugins -type f -name '*.py' -exec python {} \;
    ;;
  vm)
    venv_activate
    exec vagrant "${@:2}"
    ;;
  venv)
    if [ -n "$VIRTUAL_ENV" ]; then
      printf >&2 'You are already in a virtualenv.\n'
      exit 1
    fi
    venv_prepare
    venv_install
    venv_spawn
    ;;
  update_spellbook)
    install_spellbook;
    ;;
  exec)
    venv_activate
    export PATH="${ROOT_DIR}/tools:${PATH}"
    exec "${@:2}"
    ;;
  *)
    exit 2
    ;;
esac
