# General helpers.

# Listening TCP ports with owning process.
def ports [] {
  ^lsof -nP -iTCP -sTCP:LISTEN
  | lines | skip 1
  | parse --regex '^(?<cmd>\S+)\s+(?<pid>\d+)\s+(?<user>\S+).*?TCP (?<addr>\S+) \(LISTEN\)'
  | update pid { into int }
  | uniq
  | sort-by addr
}

# Update Homebrew and Mac App Store packages, prune caches, then show what's left outdated.
def brewup [] {
  ^brew update
  ^brew upgrade
  ^brew cleanup --prune=7
  if (which mas | is-not-empty) { ^mas upgrade }
  if (which uv | is-not-empty) { ^uv cache prune }
  ^brew outdated --json=v2 | from json | get formulae | select -o name installed_versions current_version
}

# Public IP and rough location.
def myip [] { http get https://ipinfo.io/json | select -o ip city region country org }

# Weather in the terminal (defaults to current location).
# wttr.in only returns terminal output to curl-like clients.
def weather [place: string = ""] { ^curl -fsS $"https://wttr.in/($place | url encode)?format=v2" }

# Make a directory and cd into it.
def --env mkcd [dir: path] { mkdir $dir; cd $dir }

# Launch yazi and cd into the directory navigated to on exit.
def --env yy [...args] {
  let tmp = (mktemp -t "yazi-cwd.XXXXXX")
  ^yazi ...$args --cwd-file $tmp
  let cwd = (open $tmp | str trim)
  if ($cwd | is-not-empty) and ($cwd != $env.PWD) { cd $cwd }
  rm -fp $tmp
}

# Copy the output of the last command (or nth previous command) from tmux scrollback.
def cplast [n: int = 1] {
  if ($env.TMUX? | is-empty) { error make { msg: "cplast requires tmux" } }
  let lines = (^tmux capture-pane -t $env.TMUX_PANE -p -J -S - | lines)
  let prompt_re = '(\u{f105}([ \t]|$)|^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+:.*[%#$]([ \t]|$))'
  let idxs = ($lines | enumerate | where {|r| $r.item =~ $prompt_re } | get index)
  if ($idxs | length) < ($n + 1) { error make { msg: "not enough prompts in scrollback" } }
  let start = (($idxs | get (($idxs | length) - 1 - $n)) + 1)
  let end = ($idxs | get (($idxs | length) - $n))
  let out = if $start >= $end { "" } else { $lines | slice $start..<$end | str join "\n" | str trim --right }
  $out | ^pbcopy
  let count = if ($out | is-empty) { 0 } else { $out | lines | length }
  print $"Copied ($count) line\(s\) to clipboard."
}

# Re-generate zoxide/atuin/carapace/oh-my-posh init scripts after upgrades.
def nu-refresh [] { nu-refresh-inits --force; print "Restart nu to load the new init scripts." }

# Disk usage of the current directory's children, biggest first.
def duh [] {
  ls -a | where type == dir
  | insert size_on_disk {|d| try { du $d.name | get 0.physical } catch { null } }
  | select name size_on_disk | sort-by size_on_disk -r
}

# A random developer excuse, for stand-ups.
def excuse [] {
  [
    "It works on my machine."
    "That's a caching issue."
    "DNS. It's always DNS."
    "The tests were flaky before I touched them."
    "Must be a race condition."
    "It's a feature, technically."
    "Someone changed the Terraform state."
    "OrbStack ate my container."
  ] | shuffle | first
}
