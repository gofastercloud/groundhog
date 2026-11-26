# Nushell environment.
#
# nu is always started from a zsh login shell (`zsh -l -c 'exec nu'`), so
# PATH, Homebrew, JAVA_HOME, cargo, OrbStack and ~/.local/bin all come from
# zsh/.zprofile. Only interactive-shell settings that .zshrc would normally
# export live here.

$env.EDITOR = "nvim"
$env.VISUAL = "nvim"
$env.MANPAGER = "nvim +Man!"
$env.LESS = "-RFX"
$env.PAGER = "less"
$env.NEXT_TELEMETRY_DISABLED = "1"
$env.PRIVATE_SECRETS_FILE = ($env.PRIVATE_SECRETS_FILE? | default ($env.HOME | path join ".config/private/secrets.env"))

# Secretive (Secure Enclave SSH agent): also set here so `exec nu` and direct
# nu launches pick up the socket without needing a fresh zsh login shell.
let secretive_sock = ($env.HOME | path join "Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh")
if ($secretive_sock | path exists) {
  $env.SSH_AUTH_SOCK = $secretive_sock
}

# Catppuccin Mocha for fzf (matches .zshrc).
$env.FZF_DEFAULT_OPTS = ([
  "--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8"
  "--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc"
  "--color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"
  "--color=selected-bg:#45475a"
  "--multi"
] | str join " ")

# Tool init scripts are generated once into the vendor autoload dir (loaded
# after config.nu). Run `nu-refresh-inits --force` after upgrading any of these
# tools. Nothing here depends on the terminal: which prompt is used (plain for
# mobile clients and Apple Terminal) is decided at load time by
# autoload/10-prompt.nu, so the generated files are identical for every session.
const INIT_DIR = ($nu.data-dir | path join "vendor/autoload")
const MISE_MODULE = ($nu.data-dir | path join "mise.nu")
const OMP_CONFIG = ("~/.config/oh-my-posh/catppuccin_mocha.omp.json" | path expand)

def nu-init-scripts [] {
  [
    # mise activate nu emits a Nushell module (`export def main`), so it lives
    # outside vendor/autoload and is loaded via `use` in config.nu.
    { file: "mise.nu" target: $MISE_MODULE bin: "mise" gen: {|| ^mise activate nu --quiet } }
    { file: "zoxide.nu" bin: "zoxide" gen: {|| ^zoxide init nushell } }
    { file: "atuin.nu" bin: "atuin" gen: {|| ^atuin init nu --disable-ai } }
    { file: "carapace.nu" bin: "carapace" gen: {|| ^carapace _carapace nushell } }
    { file: "oh-my-posh.nu" bin: "oh-my-posh" gen: {|| ^oh-my-posh init nu --config $OMP_CONFIG --print } }
    # nu's `ls` and completions read LS_COLORS; .zshrc's LSCOLORS is BSD-only.
    {
      file: "ls-colors.nu" bin: "vivid"
      gen: {|| ^vivid generate catppuccin-mocha }
      wrap: {|out| $"$env.LS_COLORS = ($out | str trim | to nuon)\n" }
    }
  ]
}

def nu-refresh-inits [--force (-f)] {
  mkdir $INIT_DIR
  # Clean up any old vendor/autoload/mise.nu from before mise was loaded as a module.
  rm -fp ($INIT_DIR | path join "mise.nu")
  for row in (nu-init-scripts) {
    let target = ($row.target? | default ($INIT_DIR | path join $row.file))
    if (which $row.bin | is-empty) {
      rm -f --permanent $target
      continue
    }
    # Regenerate when forced, missing or empty; keep the old file if the tool
    # fails, so a broken upgrade never leaves a half-written init script.
    let stale = $force or not ($target | path exists) or (ls $target | get 0.size) == 0b
    if $stale {
      let out = (do $row.gen | complete)
      if $out.exit_code == 0 and ($out.stdout | is-not-empty) {
        let text = (if ($row.wrap? | is-not-empty) { do $row.wrap $out.stdout } else { $out.stdout })
        $text | save -f $target
      } else {
        print -e $"nu-refresh-inits: ($row.bin) init failed: ($out.stderr | str trim)"
      }
    }
  }
}

nu-refresh-inits
