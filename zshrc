export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

plugins=(git)

source $ZSH/oh-my-zsh.sh

# Paths
export PATH=$PATH:~/.docker/bin
export PATH="${HOMEBREW_PREFIX}/opt/openssl/bin:$PATH"
export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
export PATH="$HOME/.rd/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# Java
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
export JAVA_OPTS="-Xmx16g -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005"

# Docker (Rancher Desktop)
export DOCKER_HOST=unix://$HOME/.rd/docker.sock

# Homebrew
export HOMEBREW_CASK_OPTS="--appdir=~/Applications"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Claude Code
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=32768

# Aliases
alias cursor="open -a /Applications/Cursor.app \$1"
