eval "$(/opt/homebrew/bin/brew shellenv)"
export HOMEBREW_NO_ANALYTICS=1

typeset -U path PATH

# Homebrew prefix (exported by brew shellenv above).
BREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"

# mise shims (Node and project runtimes for login/non-interactive shells and
# agents). Kept ahead of Homebrew's Node dependency.
path=("$HOME/.local/share/mise/shims" $path)

# uv (Python package manager) and user scripts.
path=("$HOME/.local/bin" $path)

# Go
path=("$HOME/go/bin" $path)

# Rust
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# Prefer the declared Homebrew JDK for command-line tools. Keep this guarded so
# a machine-specific .zshrc.local can override JAVA_HOME when required.
if [[ -z "${JAVA_HOME:-}" && -d "$BREW_PREFIX/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home" ]]; then
  export JAVA_HOME="$BREW_PREFIX/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
  path=("$JAVA_HOME/bin" $path)
fi

# Secretive (Secure Enclave SSH agent) for SSH and git commit signing.
if [[ -S "$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh" ]]; then
  export SSH_AUTH_SOCK="$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh"
fi

# Added by OrbStack: command-line tools and integration
source ~/.orbstack/shell/init.zsh 2>/dev/null || :
