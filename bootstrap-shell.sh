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
 
# Resolve the real invoking user — never fall back to root
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  USER_NAME="$SUDO_USER"
else
  # Last resort: find the first non-root user with a home directory
  USER_NAME=$(getent passwd | awk -F: '$3 >= 1000 && $7 !~ /nologin|false/ {print $1; exit}')
fi
 
if [ -z "$USER_NAME" ]; then
  echo -e "${RED}Could not determine a non-root user. Run with: sudo -E ./setup-shell.sh${NC}"
  exit 1
fi
 
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
 
if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
  echo -e "${RED}Home directory not found for user: $USER_NAME${NC}"
  exit 1
fi
 
ZSH_CUSTOM="${ZSH_CUSTOM:-$USER_HOME/.oh-my-zsh/custom}"
P10K_FILE="$USER_HOME/.p10k.zsh"
P10K_RAW_URL="https://raw.githubusercontent.com/tspyder7/bootstrap-shell/main/config/.p10k.zsh"
 
GIT_ALIAS_FILE="$ZSH_CUSTOM/git_aliases.zsh"
GIT_ALIAS_RAW_URL="https://raw.githubusercontent.com/tspyder7/bootstrap-shell/main/config/git_aliases.zsh"
 
SAFE_PKGS=(git curl)
INSTALLED_PKGS=()
 
########################################
# Detect environment: WSL2 vs native Ubuntu
########################################
IS_WSL=false
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null || \
   grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null; then
  IS_WSL=true
fi
 
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
"Configure shell switching"
"Install Git aliases"
"Install Powerlevel10k config"
)
 
UNINSTALL_TASKS=(
"Remove Oh My Zsh"
"Remove fzf"
"Remove Zsh temp files"
"Remove Git aliases"
"Remove Powerlevel10k config"
"Restore Bash shell"
"Remove shell switch config"
"Remove installed packages"
)
 
########################################
# Select task list
########################################
if [[ "$MODE" == "install" ]]; then
  TASKS=("${INSTALL_TASKS[@]}")
  $IS_WSL && TITLE="Developer Shell Setup (WSL2)" || TITLE="Developer Shell Setup (Ubuntu)"
elif [[ "$MODE" == "uninstall" ]]; then
  TASKS=("${UNINSTALL_TASKS[@]}")
  $IS_WSL && TITLE="Developer Shell Uninstall (WSL2)" || TITLE="Developer Shell Uninstall (Ubuntu)"
else
  echo "Usage: sudo $0 install|uninstall"
  exit 1
fi
 
STATUS=()
for i in "${!TASKS[@]}"; do STATUS[$i]="Pending"; done
 
########################################
# Logging helpers
########################################
log()     { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()    { echo -e "${RED}[FAIL]${NC} $1"; }
 
########################################
# run_as_user: run a command as the real user.
# Intentionally NO login flag (-) on su — avoids loading
# .profile/.bash_profile which can exit non-zero in WSL2.
########################################
run_as_user() {
  su "$USER_NAME" -s /bin/bash -c "$*"
}
 
########################################
# Helpers
########################################
install_pkg() {
  local pkg=$1

  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    return
  fi

  apt install -y "$pkg"
  INSTALLED_PKGS+=("$pkg")
}

clone_or_update() {
  local repo=$1
  local dir=$2
  if [ -d "$dir" ]; then
    git -C "$dir" pull --quiet
  else
    git clone --depth=1 "$repo" "$dir"
  fi
}
 
# Reliable on both Ubuntu and WSL2 — writes /etc/passwd directly
set_default_shell() {
  local shell_path=$1
  local user=$2
  usermod -s "$shell_path" "$user" 2>/dev/null || chsh -s "$shell_path" "$user"
}
 
########################################
# Rollback
########################################
rollback() {
  fail "Installation failed. Rolling back..."
 
  rm -rf "$USER_HOME/.oh-my-zsh"
  rm -rf "$USER_HOME/.fzf"
  rm -f "$P10K_FILE"
 
  if [ -f "$USER_HOME/.bashrc" ]; then
    sed -i '/# zsh autostart shim/,/^fi$/d' "$USER_HOME/.bashrc"
  fi
 
  for pkg in "${INSTALLED_PKGS[@]}"; do
    for safe in "${SAFE_PKGS[@]}"; do
      [[ "$pkg" == "$safe" ]] && continue 2
    done
    apt remove -y "$pkg" || true
  done
 
  set_default_shell /bin/bash "$USER_NAME" || true
 
  warn "Rollback complete"
}
 
trap 'echo -e "\n${RED}[ERROR] Command failed:${NC} \"$BASH_COMMAND\""; rollback' ERR
 
########################################
# Spinner
########################################
spinner() {
  local pid=$1
  local delay=0.1
  local spin='|/-\'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    printf "\r${YELLOW}Running %s${NC} " "${spin:$i:1}"
    sleep $delay
  done
  printf "\r"
}
 
########################################
# Draw task table
########################################
# Helper to get the visual width (strips colors and handles special chars)
# Helper to get visual width (strips colors and handles Unicode)
get_vis_len() {
  local clean=$(echo -e "$1" | sed "s/\x1b\[[0-9;]*m//g")
  # Use ${#clean} for characters, but wrap in LC_ALL=C to be safe
  echo "${#clean}"
}

draw_table() {
  printf "\033c"
  echo -e "${YELLOW}${TITLE}${NC}"

  # 1. Find Max Visual Widths
  local w1=4 # "Task"
  local w2=6 # "Status"
  for i in "${!TASKS[@]}"; do
    local t_len=$(get_vis_len "${TASKS[$i]}")
    local s_len=$(get_vis_len "${STATUS[$i]}")
    [[ $t_len -gt $w1 ]] && w1=$t_len
    [[ $s_len -gt $w2 ]] && w2=$s_len
  done

  # 2. Border Strings
  local line1=$(printf '─%.0s' $(seq 1 $((w1 + 2))))
  local line2=$(printf '─%.0s' $(seq 1 $((w2 + 2))))

  # 3. Draw Header
  printf "┌%s┬%s┐\n" "$line1" "$line2"
  
  # Manual padding for Header
  local h1_pad=$(( w1 - 4 ))
  local h2_pad=$(( w2 - 6 ))
  printf "│ Task$(printf ' %.0s' $(seq 1 $h1_pad)) │ Status$(printf ' %.0s' $(seq 1 $h2_pad)) │\n"
  
  printf "├%s┼%s┤\n" "$line1" "$line2"

  # 4. Draw Rows with Manual Padding
  for i in "${!TASKS[@]}"; do
    local t_val="${TASKS[$i]}"
    local s_val="${STATUS[$i]}"
    
    local t_vis=$(get_vis_len "$t_val")
    local s_vis=$(get_vis_len "$s_val")

    # Calculate exactly how many spaces to add
    local t_diff=$(( w1 - t_vis ))
    local s_diff=$(( w2 - s_vis ))

    # Build the padding strings
    local t_spaces=""
    [[ $t_diff -gt 0 ]] && t_spaces=$(printf ' %.0s' $(seq 1 $t_diff))
    local s_spaces=""
    [[ $s_diff -gt 0 ]] && s_spaces=$(printf ' %.0s' $(seq 1 $s_diff))

    # Print using %b to interpret the colors, but NO printf padding flags
    echo -e "│ ${t_val}${t_spaces} │ ${s_val}${s_spaces} │"
  done

  printf "└%s┴%s┘\n" "$line1" "$line2"
}

########################################
# Run task — captures stderr to a temp file
# so failures can be reported clearly
########################################
LAST_ERROR_FILE=$(mktemp)
 
run_task() {
  local index=$1
  shift
 
  STATUS[$index]="${YELLOW}Running${NC}"
  draw_table
 
  "$@" > /dev/null 2>"$LAST_ERROR_FILE" &
  pid=$!
  spinner $pid
 
  set +e
  trap - ERR
  wait $pid
  result=$?
  set -e
  trap 'echo -e "\n${RED}[ERROR] Command failed:${NC} \"$BASH_COMMAND\""; rollback' ERR
 
  if [ $result -eq 0 ]; then
    STATUS[$index]="${GREEN}✓ Done${NC}"
  else
    STATUS[$index]="${RED}✗ Failed${NC}"
  fi
 
  draw_table
 
  if [ $result -ne 0 ]; then
    echo -e "${RED}Task failed:${NC} ${TASKS[$index]}"
    if [ -s "$LAST_ERROR_FILE" ]; then
      echo -e "${RED}Error output:${NC}"
      cat "$LAST_ERROR_FILE"
    fi
    false
  fi
}
 
########################################
# Install tasks
########################################
update_packages() {
  apt update -y
}
 
install_dependencies() {
  install_pkg zsh
  install_pkg git
  install_pkg curl
  install_pkg autojump
}
 
install_ohmyzsh() {
  # Skip if already installed
  if [ -d "$USER_HOME/.oh-my-zsh" ]; then return; fi
 
  # Write the install command to a temp script so there are zero
  # quoting or variable-expansion issues when passing through su.
  local tmp_script
  tmp_script=$(mktemp /tmp/omz_install.XXXXXX.sh)
 
  cat > "$tmp_script" << INSTALLER
#!/bin/bash
# RUNZSH=no  — do not exec into zsh at the end (would hang this script)
# CHSH=yes   — let the installer call chsh to set the default shell
# HOME set   — install into the real user home, not root's
export RUNZSH=no
export CHSH=yes
export HOME="$USER_HOME"
sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
INSTALLER
 
  chmod +x "$tmp_script"
  chown "$USER_NAME:$USER_NAME" "$tmp_script"
 
  su "$USER_NAME" -s /bin/bash "$tmp_script"
  rm -f "$tmp_script"
 
  # Enforce shell change via usermod — chsh can silently fail on WSL2
  ZSH_PATH=$(which zsh)
  set_default_shell "$ZSH_PATH" "$USER_NAME"
}
 
install_powerlevel10k() {
  # Clone as root into the custom dir, then fix ownership
  clone_or_update https://github.com/romkatv/powerlevel10k.git \
    "$ZSH_CUSTOM/themes/powerlevel10k"
  chown -R "$USER_NAME:$USER_NAME" "$ZSH_CUSTOM/themes/powerlevel10k"
}
 
install_plugins() {
  clone_or_update https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
 
  clone_or_update https://github.com/zsh-users/zsh-completions \
    "$ZSH_CUSTOM/plugins/zsh-completions"
 
  clone_or_update https://github.com/zsh-users/zsh-syntax-highlighting \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
 
  chown -R "$USER_NAME:$USER_NAME" "$ZSH_CUSTOM/plugins"
}
 
install_fzf() {
  if [ -d "$USER_HOME/.fzf" ]; then return; fi
 
  # Clone as root, fix ownership, then run installer as the real user
  git clone --depth 1 https://github.com/junegunn/fzf.git "$USER_HOME/.fzf"
  chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.fzf"
 
  # Run fzf installer as the user — it writes to their shell rc files
  su "$USER_NAME" -s /bin/bash -c "'$USER_HOME/.fzf/install' --all --no-update-rc"
}
 
configure_zshrc() {
  ZSHRC="$USER_HOME/.zshrc"
 
  sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$ZSHRC" || true
 
  if grep -q '^plugins=' "$ZSHRC"; then
    sed -i 's/^plugins=.*/plugins=(git autojump zsh-autosuggestions zsh-completions zsh-syntax-highlighting)/' "$ZSHRC"
  else
    echo 'plugins=(git autojump zsh-autosuggestions zsh-completions zsh-syntax-highlighting)' >> "$ZSHRC"
  fi
 
  grep -qxF '# Powerlevel10k config' "$ZSHRC" || \
    echo -e "\n# Powerlevel10k config\n[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh" >> "$ZSHRC"
 
  grep -qxF 'source $ZSH_CUSTOM/git_aliases.zsh' "$ZSHRC" || \
    echo 'source $ZSH_CUSTOM/git_aliases.zsh' >> "$ZSHRC"
 
  cat <<EOF >> "$ZSHRC"
 
# History settings
export HISTFILESIZE=1000000000
export HISTSIZE=1000000000
setopt INC_APPEND_HISTORY
setopt HIST_FIND_NO_DUPS
EOF
 
  chown "$USER_NAME:$USER_NAME" "$ZSHRC"
}
 
configure_shell_switching() {
  # Ubuntu: usermod already wrote /etc/passwd — terminals open zsh directly. No-op.
  # WSL2:   WSL ignores /etc/passwd for interactive terminals and always spawns bash.
  #         A .bashrc exec shim is required.
  if ! $IS_WSL; then return 0; fi
 
  BASHRC="$USER_HOME/.bashrc"
 
  grep -qxF '# zsh autostart shim' "$BASHRC" && return
 
  cat <<'EOF' >> "$BASHRC"
 
# zsh autostart shim
# WSL2 ignores /etc/passwd for interactive shells and always launches bash.
# This hands off to zsh for every interactive terminal session.
if [ -t 1 ] && command -v zsh &>/dev/null && [ "$(basename "$SHELL")" != "zsh" ]; then
  exec zsh
fi
EOF
 
  chown "$USER_NAME:$USER_NAME" "$BASHRC"
}
 
install_git_aliases() {
  if [ -f "$GIT_ALIAS_FILE" ]; then return; fi
  mkdir -p "$ZSH_CUSTOM"
  curl -fsSL "$GIT_ALIAS_RAW_URL" -o "$GIT_ALIAS_FILE"
  chown "$USER_NAME:$USER_NAME" "$GIT_ALIAS_FILE"
}
 
install_p10k_config() {
  if [ -f "$P10K_FILE" ]; then return; fi
  curl -fsSL "$P10K_RAW_URL" -o "$P10K_FILE"
  chown "$USER_NAME:$USER_NAME" "$P10K_FILE"
}
 
########################################
# Uninstall tasks
########################################
remove_ohmyzsh()     { rm -rf "$USER_HOME/.oh-my-zsh"; }
remove_fzf() {
  rm -rf "$USER_HOME/.fzf"
  rm -f "$USER_HOME/.fzf.zsh"
  rm -f "$USER_HOME/.fzf.bash"
  sed -i '/fzf/d' "$USER_HOME/.zshrc" 2>/dev/null || true
}

remove_git_aliases() { rm -f "$GIT_ALIAS_FILE"; }

remove_p10k_config() { rm -f "$P10K_FILE"; }
 
remove_zsh_tmp_files() {
  rm -rf "$USER_HOME/.zshrc"
  rm -rf "$USER_HOME/.zshrc.pre-oh-my-zsh"
  rm -rf "$USER_HOME/.zsh_history"
  rm -rf "$USER_HOME/.zcompdump"*
  rm -rf "$USER_HOME/.cache/zsh"
}
 
restore_bash() {
  set_default_shell /bin/bash "$USER_NAME"
}
 
remove_shell_switch_config() {
  if ! $IS_WSL; then return 0; fi
  BASHRC="$USER_HOME/.bashrc"
  [ -f "$BASHRC" ] || return 0
  sed -i '/# zsh autostart shim/,/^fi$/d' "$BASHRC"
}
 
remove_packages() {
  for pkg in zsh autojump; do
    apt remove -y "$pkg" || true
  done
}
 
########################################
# Timer + draw initial table
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
  run_task 7 configure_shell_switching
  run_task 8 install_git_aliases
  run_task 9 install_p10k_config
 
else
 
  run_task 0 remove_ohmyzsh
  run_task 1 remove_fzf
  run_task 2 remove_zsh_tmp_files
  run_task 3 remove_git_aliases
  run_task 4 remove_p10k_config
  run_task 5 restore_bash
  run_task 6 remove_shell_switch_config
  run_task 7 remove_packages
 
fi
 
########################################
# Summary
########################################
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
rm -f "$LAST_ERROR_FILE"
 
echo
echo -e "${GREEN}✔ Completed in ${DURATION}s${NC}"
echo
 
success_count=0
fail_count=0
for s in "${STATUS[@]}"; do
  [[ "$s" == *"Done"* ]] && ((success_count+=1)) || ((fail_count+=1))
done
 
echo "Summary:"
echo "  Successful tasks : $success_count"
echo "  Failed tasks     : $fail_count"
echo
 
if [[ "$MODE" == "install" ]]; then
  echo "Next steps:"
  echo "  Restart your terminal or run: exec zsh"
  echo "  Verify active shell with:     echo \$SHELL"
  echo "  Customize Powerlevel10k with: p10k configure"
  if $IS_WSL; then
    echo ""
    echo "  WSL2: zsh will auto-launch via .bashrc shim on new terminals."
  fi
else
  echo "Next steps:"
  echo "  Restart your terminal or run: exec bash"
  echo "  Verify active shell with:     echo \$SHELL"
fi
