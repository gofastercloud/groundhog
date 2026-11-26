# OrbStack and Docker helpers, as nu tables.

# OrbStack status plus Linux machines.
def orbs [] {
  let status = (do -i { ^orb status } | complete | get stdout | str trim)
  print $"OrbStack: ($status)"
  ^orb list --format json | from json
}

# Shell into an OrbStack machine (fuzzy-pick when no name given).
def oshell [name?: string] {
  let machine = if ($name | is-empty) {
    ^orb list --format json | from json | get name | str join "\n" | ^fzf --height 30% --reverse --prompt 'machine > ' | str trim
  } else { $name }
  if ($machine | is-not-empty) { ^orb -m $machine }
}

# Running containers as a table.
def dps [--all (-a)] {
  let flags = if $all { [--all] } else { [] }
  ^docker ps ...$flags --format '{{json .}}'
  | lines | each { from json }
  | select -o Names Image State Status Ports
  | rename name image state status ports
}

# Live CPU/memory per container as a table.
def ocpu [] {
  ^docker stats --no-stream --format '{{json .}}'
  | lines | each { from json }
  | select Name CPUPerc MemUsage MemPerc
  | rename name cpu mem mem_pct
  | update cpu { str replace '%' '' | into float }
  | sort-by cpu --reverse
}

# Fuzzy-pick a running container and exec a shell in it.
def dsh [container?: string] {
  let target = if ($container | is-empty) {
    let running = (dps)
    if ($running | is-empty) { print "No running containers."; return }
    $running | get name | str join "\n" | ^fzf --height 30% --reverse --prompt 'container > ' | str trim
  } else { $container }
  if ($target | is-empty) { return }
  ^docker exec -it $target sh -c 'command -v bash >/dev/null && exec bash || exec sh'
}

# Reclaimable Docker disk space, then prune after confirmation.
# Volumes are only pruned with --volumes (they can hold data).
def dprune [--volumes] {
  ^docker system df
  let what = if $volumes { "stopped containers, dangling images, unused networks AND unused volumes" } else { "stopped containers, dangling images and unused networks" }
  if (input $"Prune ($what)? [y/N] " | str lowercase) == "y" {
    if $volumes { ^docker system prune --volumes -f } else { ^docker system prune -f }
  }
}

# Spin up a disposable, isolated container sandbox mounting ONLY the current
# directory at /workspace (zero ~/.ssh, ~/.aws, ~/.config/private, or host env).
# Network is disabled by default; pass --net only when outbound access is needed.
#   agent-box                          offline Debian shell on $PWD
#   agent-box --net                    same, with outbound network enabled
#   agent-box --image python:3.14-slim custom image
def agent-box [--net, --image: string = "debian:trixie-slim"] {
  let cwd = ($env.PWD | path expand)
  let net_flag = if $net { "bridge" } else { "none" }
  print $"Starting isolated agent-box ($image) [network=($net_flag), mount=($cwd):/workspace]"
  (
    ^docker run --rm -it --init
      --network $net_flag
      --cap-drop=ALL
      --security-opt=no-new-privileges:true
      -v $"($cwd):/workspace"
      -w /workspace
      $image
      sh -c 'command -v bash >/dev/null && exec bash || exec sh'
  )
}
