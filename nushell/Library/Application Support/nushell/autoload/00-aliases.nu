# Aliases ported from zsh/.zshrc. Differences from zsh:
# - `ls` stays nu's structured built-in; eza is `ll` / `lt` / `la`.
# - zsh's `path` alias is `paths` (nu has a built-in `path` command).
# - rm goes to the Trash (config.nu); cp/mv prompt like zsh's -i aliases.
# - `..`, `...` and bare directory names cd natively.

# Editor
alias vi = nvim
alias vim = nvim
alias v = nvim
alias view = nvim -R

# Modern CLI tools
alias bat = ^bat --paging=auto --style=plain
alias f = ^fd
alias ll = ^eza -lah --group-directories-first --icons=auto
alias la = ^eza -a --group-directories-first --icons=auto
alias lt = ^eza -T --group-directories-first --icons=auto
alias cp = cp --interactive
alias mv = mv --interactive

# Quality of life
alias c = clear
alias j = job list
def h [n: int = 25] { history | last $n }
def paths [] { $env.PATH | enumerate | rename idx dir }

# Git (same names as zsh; richer versions in git.nu)
alias gs = ^git status -sb
alias ga = ^git add
alias gc = ^git commit
alias gca = ^git commit --amend
alias gp = ^git push
alias gl = ^git log --oneline --graph --decorate
alias gco = ^git checkout
alias gb = ^git branch
alias gd = ^git diff
alias gdft = ^git -c diff.external=difft diff

# Docker Compose (OrbStack-friendly)
alias dcu = ^docker compose up -d
alias dcd = ^docker compose down
alias dcs = ^docker compose ps
alias dcl = ^docker compose logs
alias dcf = ^docker compose logs -f
alias dcr = ^docker compose restart
alias dcb = ^docker compose build
alias dcub = ^docker compose up -d --build
alias dce = ^docker compose exec
alias dceb = ^docker compose exec backend /bin/bash
alias dcesh = ^docker compose exec backend /bin/sh
