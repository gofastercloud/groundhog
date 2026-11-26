#!/usr/bin/env bash
# Load the repo's nushell config the way an interactive nu does (env.nu,
# config.nu, generated vendor init scripts, then autoload/*.nu) in an
# isolated XDG home, and require it to produce no output except "ok".
# `nu -c` skips autoload, so the files are sourced explicitly in load order.
set -euo pipefail

NU_DIR="$1"
tmp=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/nucheck.XXXXXX")" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
export XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data"
mkdir -p "$XDG_CONFIG_HOME/nushell"
cp -R "$NU_DIR"/. "$XDG_CONFIG_HOME/nushell/"
NU_DIR="$XDG_CONFIG_HOME/nushell"
nu_flags=(--env-config "$NU_DIR/env.nu" --config "$NU_DIR/config.nu")

data_dir=$(nu "${nu_flags[@]}" -c 'print $nu.data-dir')
[[ "$data_dir" == "$tmp"/* ]] || { echo "nu data dir not isolated: $data_dir" >&2; exit 1; }

check="$tmp/check.nu"
for f in "$data_dir"/vendor/autoload/*.nu "$NU_DIR"/autoload/*.nu; do
    [[ -e "$f" ]] && printf 'source "%s"\n' "$f"
done > "$check"
cat >> "$check" <<'NU'
let want = [gst glog gsw gclean gwt orbs dps with-secrets ports nu-refresh-inits]
let missing = ($want | where {|c| scope commands | where name == $c | is-empty })
if ($missing | is-not-empty) { print $"missing commands: ($missing)"; exit 1 }
if (scope aliases | where name == ll | is-empty) { print "missing alias: ll"; exit 1 }
print ok
NU

out=$(nu "${nu_flags[@]}" "$check" 2>&1)
if [[ "$out" != ok ]]; then
    echo "$out" >&2
    exit 1
fi

# The generated init scripts are terminal-independent; autoload/10-prompt.nu
# picks the prompt. PROMPT_COMMAND_RIGHT is a closure for oh-my-posh, a string
# for the plain mobile prompt and unset for Apple Terminal (nu's built-in).
prompt_check="$tmp/prompt.nu"
{
    for f in "$data_dir"/vendor/autoload/*.nu "$NU_DIR"/autoload/*.nu; do
        [[ -e "$f" ]] && printf 'source "%s"\n' "$f"
    done
    echo 'print ($env.PROMPT_COMMAND_RIGHT? | describe)'
} > "$prompt_check"

check_prompt() {
    local expected=$1
    shift
    local actual
    actual=$(env "$@" nu "${nu_flags[@]}" "$prompt_check" 2>&1)
    if [[ "$actual" != "$expected" ]]; then
        echo "prompt for $*: expected $expected, got: $actual" >&2
        exit 1
    fi
    # A real interactive login start must be silent too.
    actual=$(env "$@" nu -l -i -c exit 2>&1)
    if [[ -n "$actual" ]]; then
        echo "nu -l -i -c exit printed output for $*: $actual" >&2
        exit 1
    fi
}

if command -v oh-my-posh >/dev/null; then
    check_prompt closure -u MOBILE TERM_PROGRAM=ghostty
    check_prompt string TERM_PROGRAM=ghostty MOBILE=1
fi
check_prompt nothing -u MOBILE TERM_PROGRAM=Apple_Terminal
