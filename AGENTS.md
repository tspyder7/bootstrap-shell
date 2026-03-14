# AGENTS.md - Developer Shell Setup

## Project Overview

This is a Bash shell script project that automates the setup of a developer environment with Zsh, Oh My Zsh, Powerlevel10k theme & plugins on Ubuntu/Debian systems.

## Build / Lint / Test Commands

### Linting

```bash
# Install shellcheck (static analysis for shell scripts)
sudo apt install shellcheck

# Run shellcheck on all shell scripts
shellcheck bootstrap-shell.sh

# Install shfmt (shell formatter)
go install mvdan.cc/sh/v3/cmd/shfmt@latest

# Format shell scripts (indents, aligns)
shfmt -w -i 2 -ci bootstrap-shell.sh

# Check formatting without writing
shfmt -d bootstrap-shell.sh
```

### Testing

This project does not have formal tests. For manual testing:

```bash
# Dry run (review what would be executed)
sudo bash -n bootstrap-shell.sh  # syntax check only

# The script requires root (sudo) and modifies the system
# Test in a VM or container
sudo ./bootstrap-shell.sh install
sudo ./bootstrap-shell.sh uninstall
```

## Code Style Guidelines

### General Principles

- Use `set -Eeuo pipefail` at the script top for strict error handling
- Use `#!/usr/bin/env bash` shebang for portability
- Use 2-space indentation (standard for shell)
- Keep lines under 100 characters when practical
- Use all-caps for constants, lowercase for variables

### Functions

- Define functions before they are called
- Use descriptive names: `install_pkg()`, `clone_or_update()`
- Use local variables inside functions: `local var_name`
- Return explicit exit codes: `return 0` or `return 1`

### Variables

- Quote variables to handle spaces: `"$var"` not `$var`
- Use `${var}` for clarity in strings: `"${USER_HOME}/.zsh"`
- Uppercase for constants: `GREEN`, `RED`, `NC` (color codes)
- Lowercase for runtime variables: `mode`, `status`, `tasks`

### Conditionals

- Use `[[ ]]` for tests (Bash-native, safer than `[ ]`)
- Use `[[ "$var" == "value" ]]` not `[[ $var == value ]]`
- Quote variables in conditionals: `[[ "$var" ]]`
- Use `-z` for empty check, `-n` for non-empty

### Error Handling

- Always handle errors with `trap` for cleanup
- Use `command -v` to check if commands exist
- Redirect stderr where appropriate: `> /dev/null 2>&1`
- Provide meaningful error messages with colors

### Imports / External Scripts

- No external dependencies beyond standard Unix tools
- Use `curl -fsSL` for secure downloads (fail silent, follow redirects)
- Use `--depth 1` for git clones when full history isn't needed

### Strings

- Use single quotes for literal strings: `'literal $noexpand'`
- Use double quotes for strings with variables: `"$var expand"`
- Use heredocs for multi-line content: `cat <<EOF ... EOF`

### Arrays

- Use arrays for lists: `TASKS=(task1 task2 task3)`
- Index with `${!array[@]}` for keys, `${array[@]}` for values
- Quote array expansions: `"${array[@]}"`

### Command Execution

- Use `&` for background processes: `cmd &`
- Capture PID with `$!` for process management
- Use `wait $pid` to wait for background jobs
- Check exit codes: `cmd; result=$?`

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Functions | snake_case, verb | `install_pkg`, `clone_or_update` |
| Variables | snake_case | `user_home`, `installed_pkgs` |
| Constants | UPPER_SNAKE | `GREEN`, `NC` |
| Files | kebab-case | `bootstrap-shell.sh` |

### Color Codes

Use these standard ANSI colors (define at top):

```bash
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"  # No Color
```

### Logging Functions

Create helper functions for consistent output:

```bash
log()   { echo -e "${BLUE}[INFO]${NC} $1"; }
success(){ echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; }
```

### Patterns to Avoid

- Don't use `eval` unless absolutely necessary
- Don't use backticks; use `$(command)` instead
- Don't use `cd` in scripts; use absolute paths
- Don't leave debug code (`set -x`) in committed code

### File Organization

1. Shebang and error handling
2. Constants (colors, defaults)
3. Global variables
4. Helper functions
5. Task implementations
6. Main execution flow

### Best Practices

- Always check for root (`EUID -eq 0`) when needed
- Use `--quiet` or `--depth 1` for faster git operations
- Clean up on failure with trap
- Provide usage message for invalid arguments
- Print summary statistics at end
