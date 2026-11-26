################################################################
# Modern zsh config – macOS, Homebrew, Atuin, Zoxide, fzf, etc.
################################################################

# Keep PATH-like arrays ordered and duplicate-free.
typeset -U path PATH

############################
# Homebrew prefix & completion paths
############################
# PATH itself (Homebrew, ~/.local/bin, Go, cargo, JAVA_HOME) is set once in
# .zprofile; only the completion search path is extended here.
if command -v brew &>/dev/null; then
  export BREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"

  # Completion functions from Homebrew formulas
  fpath=(
    "$BREW_PREFIX/share/zsh/site-functions"
    "$BREW_PREFIX/share/zsh-completions"
    $fpath
  )
fi

# User completions (your own `_tool` files live here)
fpath=("$HOME/.zsh/completions" $fpath)


############################
# zsh options (sane defaults)
############################
setopt AUTO_CD              # `cd dir` -> just `dir`
setopt AUTO_PUSHD           # maintain directory stack
setopt PUSHD_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_IGNORE_SPACE     # leading-space commands stay out of native history
setopt SHARE_HISTORY        # share history between sessions
setopt NO_BANG_HIST  # Disables ! expansion

# History size
HISTSIZE=100000
SAVEHIST=100000
HISTFILE="$HOME/.zsh_history"


############################
# Completion system
############################
autoload -Uz compinit
setopt EXTENDED_GLOB
ZSH_COMPDUMP="$HOME/.zcompdump"
if [[ ! -r "$ZSH_COMPDUMP" ||
      ( -d "$HOME/.zsh/completions" && "$HOME/.zsh/completions" -nt "$ZSH_COMPDUMP" ) ||
      ( -n "${BREW_PREFIX:-}" && -d "$BREW_PREFIX/share/zsh/site-functions" && "$BREW_PREFIX/share/zsh/site-functions" -nt "$ZSH_COMPDUMP" ) ||
      ( -n "${BREW_PREFIX:-}" && -d "$BREW_PREFIX/share/zsh-completions" && "$BREW_PREFIX/share/zsh-completions" -nt "$ZSH_COMPDUMP" ) ]]; then
  compinit
else
  compinit -C
fi
unsetopt EXTENDED_GLOB

zsh-completion-refresh() {
  rm -f "$ZSH_COMPDUMP"
  autoload -Uz compinit
  compinit
}

# If compinit reports insecure directories, run ONCE:
#   compaudit | xargs chmod g-w

# Completion behaviour & dotfiles
unsetopt MENU_COMPLETE
unsetopt CORRECT
unsetopt CORRECT_ALL
setopt AUTO_MENU                           # show menu when multiple matches
setopt GLOB_DOTS                           # include dotfiles in globbing
zstyle ':completion:*' menu select         # interactive completion menu
zstyle ':completion:*' special-dirs false  # do not include . and .. in dirs
zstyle ':completion:*' matcher-list '' \
  'm:{a-zA-Z}={A-Za-z}' \
  'm:{a-zA-Z-.}={A-Za-z-.}'

# fzf-tab should see hidden files too
zstyle ':completion:*' fzf-file-opts --hidden --follow


############################
# Atuin (smart history)
############################
if command -v atuin &>/dev/null; then
  eval "$(atuin init zsh --disable-ai)"
fi


############################
# Zoxide (smarter cd)
############################
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
fi


############################
# fzf (fuzzy finder)
############################
# Catppuccin Mocha colors for fzf
export FZF_DEFAULT_OPTS=" \
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
  --color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
  --color=selected-bg:#45475a \
  --multi"

if [ -n "$BREW_PREFIX" ]; then
  # fzf key bindings (Ctrl-T, Alt-C, etc).
  # Atuin will typically handle Ctrl-R for history search.
  if [ -f "$BREW_PREFIX/opt/fzf/shell/key-bindings.zsh" ]; then
    source "$BREW_PREFIX/opt/fzf/shell/key-bindings.zsh"
  fi
fi


############################
# fzf-tab (fuzzy completion)
############################
# Manually cloned to ~/.zsh/plugins/fzf-tab
if [ -f "$HOME/.zsh/plugins/fzf-tab/fzf-tab.plugin.zsh" ]; then
  source "$HOME/.zsh/plugins/fzf-tab/fzf-tab.plugin.zsh"
fi


############################
# mise (polyglot runtime manager)
############################
if command -v mise &>/dev/null; then
  eval "$(mise activate zsh)"
fi


############################
# Environment / colour settings
############################
# Disable Next.js telemetry
export NEXT_TELEMETRY_DISABLED=1

# Colours for basic tools (ls, etc.)
export CLICOLOR=1
export LSCOLORS=exfxcxdxbxegedabagacad

# Less: raw colour (-R), quit if one screen (-F), no beeps (-X)
export LESS='-RFX'
export PAGER='less'


############################
# Default editor: Neovim
############################
export EDITOR="nvim"
export VISUAL="nvim"
export MANPAGER="nvim +Man!"   # view man pages in neovim

# vi / vim aliases -> nvim
if command -v nvim &>/dev/null; then
  alias vi='nvim'
  alias vim='nvim'
  alias view='nvim -R'
  alias v='nvim'
fi


############################
# Minimal fallback aliases
############################
# zsh is only the login/fallback shell; nushell (autoload/00-aliases.nu) is the
# interactive shell and owns the full alias set. Keep just enough here for
# when nu is unavailable or bypassed (DOTFILES_SHELL=zsh, recovery, ssh).
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


############################
# Prompt (oh-my-posh, with mobile fallback)
############################
# Mobile clients (Prompt 3 on iOS) set MOBILE=1 in their connection command.
# Their fonts don't carry Nerd-Font glyphs, so use a plain prompt instead.
if [ -n "$MOBILE" ]; then
  PROMPT='%F{cyan}%n@%m%f:%F{yellow}%~%f %# '
  RPROMPT=''
elif [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
  if command -v oh-my-posh &>/dev/null; then
    eval "$(oh-my-posh init zsh --config ${XDG_CONFIG_HOME:-$HOME/.config}/oh-my-posh/catppuccin_mocha.omp.json)"
  fi
fi


############################
# Fast syntax highlighting (LAST)
############################
# From: brew install zsh-fast-syntax-highlighting
if [ -n "$BREW_PREFIX" ]; then
  FSH="$BREW_PREFIX/opt/zsh-fast-syntax-highlighting/share/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"
  if [ -f "$FSH" ]; then
    source "$FSH"
  fi
fi


############################
# Scoped secrets
############################
# Secrets are loaded only for an explicit command or subshell. This avoids
# leaking every credential into every interactive process.
PRIVATE_SECRETS_FILE="${PRIVATE_SECRETS_FILE:-$HOME/.config/private/secrets.env}"

with-secrets() {
  if (( $# == 0 )); then
    echo "usage: with-secrets <command> [args...]" >&2
    return 2
  fi
  if [[ ! -r "$PRIVATE_SECRETS_FILE" ]]; then
    echo "secrets file is not readable: $PRIVATE_SECRETS_FILE" >&2
    return 1
  fi

  (
    set -a
    source "$PRIVATE_SECRETS_FILE"
    set +a
    command "$@"
  )
}

secrets-shell() {
  with-secrets "${SHELL:-/bin/zsh}" -l
}


############################
# Machine-specific overrides
############################
# For machine-specific settings (like external SSD paths),
# create ~/.zshrc.local with your customizations
if [ -f "$HOME/.zshrc.local" ]; then
  source "$HOME/.zshrc.local"
fi
