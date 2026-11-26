################################################################
# Minimal fallback zsh config (Nushell is the primary shell)
#
# PATH, Homebrew, mise shims, JAVA_HOME, SSH_AUTH_SOCK, and OrbStack
# are set once in .zprofile (sourced by login shells and interactive-shell).
# This file keeps a lean, fast interactive fallback for DOTFILES_SHELL=zsh,
# recovery sessions, or POSIX-only tooling.
################################################################

typeset -U path PATH

# Sane history and navigation defaults
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt NO_BANG_HIST

HISTSIZE=50000
SAVEHIST=50000
HISTFILE="$HOME/.zsh_history"

# Lightweight completion (no external plugin clones)
autoload -Uz compinit
compinit -C

# Tool integrations (guarded for graceful degradation)
if command -v atuin &>/dev/null; then
  eval "$(atuin init zsh --disable-ai)"
fi

if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
fi

if command -v mise &>/dev/null; then
  eval "$(mise activate zsh)"
fi

# Catppuccin Mocha colours for fzf
export FZF_DEFAULT_OPTS=" \
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
  --color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
  --color=selected-bg:#45475a \
  --multi"

# Environment & editor defaults
export NEXT_TELEMETRY_DISABLED=1
export CLICOLOR=1
export LSCOLORS=exfxcxdxbxegedabagacad
export LESS='-RFX'
export PAGER='less'
export EDITOR="nvim"
export VISUAL="nvim"
export MANPAGER="nvim +Man!"

# Minimal fallback aliases (full alias set lives in nushell)
if command -v nvim &>/dev/null; then
  alias vi='nvim'
  alias vim='nvim'
  alias view='nvim -R'
  alias v='nvim'
fi

if command -v eza &>/dev/null; then
  alias ll='eza -lah --group-directories-first --icons=auto'
else
  alias ll='ls -lah'
fi
alias ..='cd ..'
alias ...='cd ../..'
alias gs='git status -sb'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate'

# Prompt (oh-my-posh, with plain fallback for mobile / Apple Terminal)
if [[ -n "${MOBILE:-}" || "${TERM_PROGRAM:-}" == "Apple_Terminal" ]]; then
  PROMPT='%F{cyan}%n@%m%f:%F{yellow}%~%f %# '
  RPROMPT=''
elif command -v oh-my-posh &>/dev/null; then
  eval "$(oh-my-posh init zsh --config "${XDG_CONFIG_HOME:-$HOME/.config}/oh-my-posh/catppuccin_mocha.omp.json")"
fi

# Machine-specific overrides
if [[ -f "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi
