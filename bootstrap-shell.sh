#!/usr/bin/env bash

set -Eeuo pipefail

########################################
# Colors
########################################
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

########################################
# Root check
########################################
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run with sudo${NC}"
  exit 1
fi

MODE=${1:-install}
USER_HOME=$(eval echo ~${SUDO_USER})
USER_NAME=$SUDO_USER
ZSH_CUSTOM="${ZSH_CUSTOM:-$USER_HOME/.oh-my-zsh/custom}"
P10K_FILE="$USER_HOME/.p10k.zsh"
P10K_RAW_URL="https://raw.githubusercontent.com/tspyder7/bootstrap-shell/refs/heads/main/config/.p10k.zsh"

SAFE_PKGS=(git curl)
INSTALLED_PKGS=()

########################################
# Task lists
########################################
INSTALL_TASKS=(
"Update package list"
"Install dependencies"
"Install Oh My Zsh"
"Install Powerlevel10k"
"Install Zsh plugins"
"Install fzf"
"Configure .zshrc"
"Install Powerlevel10k config"
)

UNINSTALL_TASKS=(
"Remove Oh My Zsh"
"Remove fzf"
"Remove Powerlevel10k config"
"Restore Bash shell"
"Remove installed packages"
)

########################################
# Select task list
########################################
if [[ "$MODE" == "install" ]]; then
  TASKS=("${INSTALL_TASKS[@]}")
  TITLE="Developer Shell Setup"
elif [[ "$MODE" == "uninstall" ]]; then
  TASKS=("${UNINSTALL_TASKS[@]}")
  TITLE="Developer Shell Uninstall"
else
  echo "Usage: sudo $0 install|uninstall"
  exit 1
fi

STATUS=()
for i in "${!TASKS[@]}"; do STATUS[$i]="Pending"; done

########################################
# Helpers
########################################
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

install_pkg() {
  pkg=$1
  if dpkg -s "$pkg" >/dev/null 2>&1; then return; fi
  apt install -y "$pkg"
  INSTALLED_PKGS+=("$pkg")
}

clone_or_update() {
  repo=$1
  dir=$2
  if [ -d "$dir" ]; then
    git -C "$dir" pull --quiet
  else
    git clone --depth=1 "$repo" "$dir"
  fi
}

########################################
# Rollback on error
########################################
rollback() {
  fail "Installation failed. Rolling back..."

  rm -rf "$USER_HOME/.oh-my-zsh"
  rm -rf "$USER_HOME/.fzf"
  rm -f "$P10K_FILE"

  for pkg in "${INSTALLED_PKGS[@]}"; do
    for safe in "${SAFE_PKGS[@]}"; do
      [[ "$pkg" == "$safe" ]] && continue 2
    done
    apt remove -y "$pkg" || true
  done

  chsh -s /bin/bash "$USER_NAME" || true
  warn "Rollback complete"
}

trap rollback ERR

########################################
# Spinner
########################################
spinner() {
  pid=$1
  delay=0.1
  spin='-\|/'
  i=0

  while kill -0 $pid 2>/dev/null; do
    i=$(( (i+1) %4 ))
    printf "\r${YELLOW}Running ${spin:$i:1}${NC}"
    sleep $delay
  done

  printf "\r"
}

########################################
# Draw task table
########################################
draw_table() {
  clear
  echo -e "${BLUE}${TITLE}${NC}\n"

  printf "┌───────────────────────────────┬────────────┐\n"
  printf "│ %-29s │ %-10s │\n" "Task" "Status"
  printf "├───────────────────────────────┼────────────┤

"
  for i in "${!TASKS[@]}"; do
    printf "│ %-29s │ %-10b │\n" "${TASKS[$i]}" "${STATUS[$i]}"
  done
  printf "└───────────────────────────────┴────────────┘\n"
}

run_task() {
  index=$1
  shift

  STATUS[$index]="${YELLOW}Running${NC}"
  draw_table

  "$@" > /dev/null 2>&1 &
  pid=$!

  spinner $pid
  wait $pid
  result=$?

  STATUS[$index]=$([ $result -eq 0 ] && echo "${GREEN}✓ Done${NC}" || echo "${RED}✗ Failed${NC}")

  draw_table
}

########################################
# Install tasks
########################################
update_packages() { apt update -y; }

install_dependencies() {
  install_pkg zsh
  install_pkg git
  install_pkg curl
  install_pkg autojump
}

install_ohmyzsh() {
  if [ -d "$USER_HOME/.oh-my-zsh" ]; then return; fi
  sudo -u "$SUDO_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
}

install_powerlevel10k() {
  clone_or_update https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
}

install_plugins() {
  clone_or_update https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  clone_or_update https://github.com/zsh-users/zsh-completions "$ZSH_CUSTOM/plugins/zsh-completions"
  clone_or_update https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
}

install_fzf() {
  if [ -d "$USER_HOME/.fzf" ]; then return; fi

  sudo -u "$SUDO_USER" git clone --depth 1 https://github.com/junegunn/fzf.git "$USER_HOME/.fzf"
  sudo -u "$SUDO_USER" "$USER_HOME/.fzf/install" --all
}

configure_zshrc() {
  ZSHRC="$USER_HOME/.zshrc"

  sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$ZSHRC" || true

  if grep -q '^plugins=' "$ZSHRC"; then
    sed -i 's/^plugins=.*/plugins=(git autojump zsh-autosuggestions zsh-completions zsh-syntax-highlighting)/' "$ZSHRC"
  else
    echo 'plugins=(git autojump zsh-autosuggestions zsh-completions zsh-syntax-highlighting)' >> "$ZSHRC"
  fi

  grep -qxF '# Powerlevel10k config' "$ZSHRC" || echo -e "\n# Powerlevel10k config\n[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh" >> "$ZSHRC"

  cat <<EOF >> "$ZSHRC"

# History settings
export HISTFILESIZE=1000000000
export HISTSIZE=1000000000
setopt INC_APPEND_HISTORY
setopt HIST_FIND_NO_DUPS
EOF
}

install_p10k_config() {
  if [ -f "$P10K_FILE" ]; then return; fi
  sudo -u "$SUDO_USER" curl -fsSL "$P10K_RAW_URL" -o "$P10K_FILE"
}

########################################
# Uninstall tasks
########################################
remove_ohmyzsh() {
  rm -rf "$USER_HOME/.oh-my-zsh"
}

remove_fzf() {
  rm -rf "$USER_HOME/.fzf"
}

remove_p10k_config() {
  rm -f "$P10K_FILE"
}

restore_bash() {
  chsh -s /bin/bash "$USER_NAME"
}

remove_packages() {
  for pkg in zsh autojump; do
    apt remove -y "$pkg" || true
  done
}

########################################
# Timer
########################################
START_TIME=$(date +%s)

draw_table

########################################
# Execute tasks
########################################
if [[ "$MODE" == "install" ]]; then
  run_task 0 update_packages
  run_task 1 install_dependencies
  run_task 2 install_ohmyzsh
  run_task 3 install_powerlevel10k
  run_task 4 install_plugins
  run_task 5 install_fzf
  run_task 6 configure_zshrc
  run_task 7 install_p10k_config

else
  run_task 0 remove_ohmyzsh
  run_task 1 remove_fzf
  run_task 2 remove_p10k_config
  run_task 3 restore_bash
  run_task 4 remove_packages
fi

########################################
# Summary
########################################
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo
echo -e "${GREEN}✔ Completed in ${DURATION}s${NC}"
echo

success_count=0
fail_count=0

for s in "${STATUS[@]}"; do
  [[ "$s" == *"Done"* ]] && ((success_count++)) || ((fail_count++))
done

echo "Summary:"
echo "Successful tasks: $success_count"
echo "Failed tasks: $fail_count"
echo

if [[ "$MODE" == "install" ]]; then
  echo "Restart terminal or run: exec zsh"
  echo "For Powerlevel10k custom configuration: p10k configure"
fi