# Structured git helpers. Everything returns nu tables, so you can pipe:
#   gst | where status =~ M
#   glog 50 | where author == "you" | first 5

# Working-tree status as a table.
def gst [] {
  ^git status --porcelain=v1
  | lines
  | parse --regex '^(?<index>.)(?<tree>.) (?<file>.+)$'
  | insert status {|r|
      match ([$r.index $r.tree] | str join) {
        "??" => "untracked"
        $s if ($s =~ "U") or $s in ["AA" "DD"] => "conflict"
        $s if ($s | str starts-with "A") => "added"
        $s if ($s =~ "D") => "deleted"
        $s if ($s =~ "R") => "renamed"
        _ => "modified"
      }
    }
  | insert staged {|r| $r.index not-in [" " "?"] }
  | select status staged file
}

# Recent commits as a table.
def glog [n: int = 20] {
  ^git log $"-($n)" --pretty=format:'%h%x1f%an%x1f%aI%x1f%s'
  | lines
  | split column (char -u '1f') hash author date subject
  | update date { into datetime }
}

# Local branches with upstream tracking state, newest first.
def gbr [] {
  ^git for-each-ref --sort=-committerdate refs/heads --format='%(refname:short)%1f%(upstream:short)%1f%(upstream:track)%1f%(committerdate:iso-strict)%1f%(HEAD)'
  | lines
  | split column (char -u '1f') branch upstream track date current
  | update date { into datetime }
  | update current { $in == "*" }
  | insert gone {|r| $r.track == "[gone]" }
}

# Fuzzy-switch branch (local or remote) with a log preview.
def gsw [] {
  let pick = (
    ^git branch --all --sort=-committerdate --format='%(refname:short)'
    | lines | where $it != "origin/HEAD" and $it != "origin"
    | str join "\n"
    | ^fzf --height 40% --reverse --prompt 'branch > ' --preview 'git log --oneline --graph --color=always -20 {}'
    | str trim
  )
  if ($pick | is-empty) { return }
  ^git switch ($pick | str replace --regex '^origin/' '')
}

# Delete local branches that are merged into the default branch or whose
# upstream is gone. Shows the list and asks first; --dry-run only lists.
def gclean [--dry-run (-n)] {
  ^git fetch --prune --quiet
  let main = (gmain)
  let merged = (^git branch --merged $main --format='%(refname:short)' | lines)
  let doomed = (
    gbr
    | where not current and branch != $main
    | where gone or branch in $merged
    | select branch track date
  )
  if ($doomed | is-empty) { print "Nothing to clean."; return }
  print $doomed
  if $dry_run { return }
  if (input $"Delete ($doomed | length) branch\(es\)? [y/N] " | str lowercase) == "y" {
    $doomed.branch | each {|b| ^git branch -D $b } | ignore
  }
}

# Name of the default branch (main/master/...).
def gmain [] {
  let ref = (do -i { ^git symbolic-ref --quiet refs/remotes/origin/HEAD } | complete)
  if $ref.exit_code == 0 { $ref.stdout | str trim | str replace 'refs/remotes/origin/' '' } else { "main" }
}

# Worktrees as a table, or add/open/remove one (ideal for parallel coding agents).
#   gwt                       list worktrees
#   gwt add feat/x            new worktree at ../<repo>-feat-x on a new branch
#   gwt add feat/x --sesh     same, and open it in a dedicated sesh/tmux session
#   gwt open feat/x           open an existing worktree in sesh/tmux
#   gwt rm feat/x             remove worktree for branch
# If the repo contains a `.worktreeinclude` file (one relative path per line),
# listed untracked files are copied into the new worktree automatically.
def --env gwt [action?: string, branch?: string, --sesh (-s)] {
  if $action in [add open rm] and ($branch | is-empty) {
    error make { msg: $"usage: gwt ($action) <branch>" }
  }
  match $action {
    null | "ls" => {
      ^git worktree list --porcelain
      | split row "\n\n" | where $it != ""
      | each {|blk|
          let kv = ($blk | lines | parse '{k} {v}' | transpose -rd)
          { path: $kv.worktree, branch: ($kv.branch? | default "(detached)" | str replace 'refs/heads/' ''), head: ($kv.HEAD? | default "" | str substring 0..6) }
        }
    }
    "add" => {
      let root = (^git rev-parse --show-toplevel | str trim)
      let dir = ($root | path dirname | path join $"($root | path basename)-($branch | str replace -a '/' '-')")
      ^git worktree add -b $branch $dir
      let inc = ($root | path join ".worktreeinclude")
      if ($inc | path exists) {
        for rel in (open --raw $inc | lines | each { str trim } | where {|l| ($l | is-not-empty) and (not ($l | str starts-with "#")) }) {
          let src = ($root | path join $rel)
          let dst = ($dir | path join $rel)
          if ($src | path exists) {
            mkdir ($dst | path dirname)
            cp -r $src $dst
          }
        }
      }
      if $sesh and (which sesh | is-not-empty) {
        ^sesh connect $dir
      } else {
        cd $dir
      }
    }
    "open" => {
      let wt = (gwt | where branch == $branch)
      if ($wt | is-empty) { error make { msg: $"no worktree for ($branch)" } }
      let target = ($wt | first | get path)
      if (which sesh | is-not-empty) { ^sesh connect $target } else { cd $target }
    }
    "rm" => {
      let wt = (gwt | where branch == $branch)
      if ($wt | is-empty) { error make { msg: $"no worktree for ($branch)" } }
      ^git worktree remove ($wt | first | get path)
    }
    _ => { error make { msg: "usage: gwt [ls|add <branch> [--sesh]|open <branch>|rm <branch>]" } }
  }
}

# Open (or create) the PR for the current branch in the browser.
def gpr [] {
  let view = (do -i { ^gh pr view --web } | complete)
  if $view.exit_code != 0 { ^gh pr create --web }
}

# Who touched this repo most, by commits.
def gwho [n: int = 10] {
  ^git shortlog -sne --all
  | lines | parse --regex '^\s*(?<commits>\d+)\s+(?<author>.+)$'
  | update commits { into int }
  | first $n
}

# Jump to the repo root.
def --env groot [] { cd (^git rev-parse --show-toplevel | str trim) }
