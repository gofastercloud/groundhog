# Nushell interactive config. Nushell's built-in defaults apply first; only
# overrides live here. Aliases and custom commands are in ./autoload/.

$env.config.show_banner = false
$env.config.edit_mode = "emacs"
$env.config.buffer_editor = "nvim"
$env.config.footer_mode = "auto"
$env.config.table.mode = "rounded"
$env.config.datetime_format.normal = "%Y-%m-%d %H:%M"

# History: sqlite, shared across sessions as they run (zsh SHARE_HISTORY).
# Atuin still owns Ctrl-R and the up arrow.
$env.config.history.file_format = "sqlite"
$env.config.history.max_size = 100_000
$env.config.history.isolation = false

# Completions: carapace (vendor/autoload/carapace.nu) is the external completer,
# case-insensitive like the zsh matcher-list.
$env.config.completions.case_sensitive = false
$env.config.completions.algorithm = "fuzzy"
$env.config.completions.quick = true
$env.config.completions.partial = true

# `rm` goes to the macOS Trash by default; `rm --permanent` to really delete.
$env.config.rm.always_trash = true

$env.config.cursor_shape.emacs = "line"
$env.config.use_kitty_protocol = true

# Catppuccin Mocha
let mocha = {
  rosewater: "#f5e0dc" flamingo: "#f2cdcd" pink: "#f5c2e7" mauve: "#cba6f7"
  red: "#f38ba8" maroon: "#eba0ac" peach: "#fab387" yellow: "#f9e2af"
  green: "#a6e3a1" teal: "#94e2d5" sky: "#89dceb" sapphire: "#74c7ec"
  blue: "#89b4fa" lavender: "#b4befe" text: "#cdd6f4" subtext0: "#a6adc8"
  overlay0: "#6c7086" surface1: "#45475a" surface0: "#313244" base: "#1e1e2e"
}
$env.config.color_config = {
  separator: $mocha.overlay0
  leading_trailing_space_bg: $mocha.surface0
  header: { fg: $mocha.mauve attr: b }
  empty: $mocha.overlay0
  bool: $mocha.peach
  int: $mocha.peach
  float: $mocha.peach
  filesize: $mocha.sky
  duration: $mocha.teal
  datetime: $mocha.lavender
  range: $mocha.peach
  string: $mocha.green
  nothing: $mocha.overlay0
  binary: $mocha.peach
  cell-path: $mocha.text
  row_index: { fg: $mocha.overlay0 }
  record: $mocha.text
  list: $mocha.text
  hints: $mocha.overlay0
  search_result: { fg: $mocha.base bg: $mocha.yellow }
  shape_external: $mocha.blue
  shape_external_resolved: { fg: $mocha.blue attr: b }
  shape_internalcall: { fg: $mocha.mauve attr: b }
  shape_string: $mocha.green
  shape_filepath: $mocha.sapphire
  shape_directory: $mocha.sapphire
  shape_flag: $mocha.peach
  shape_variable: $mocha.lavender
  shape_garbage: { fg: $mocha.base bg: $mocha.red attr: b }
}

# Ctrl-T: fzf file picker inserted at the cursor (zsh's fzf key binding).
$env.config.keybindings ++= [
  {
    name: fzf_file
    modifier: control
    keycode: char_t
    mode: [emacs vi_insert]
    event: {
      send: executehostcommand
      cmd: "commandline edit --insert (^fd --type f --hidden --follow --exclude .git | ^fzf --height 40% --reverse | str trim)"
    }
  }
  {
    name: fzf_cd
    modifier: alt
    keycode: char_c
    mode: [emacs vi_insert]
    event: {
      send: executehostcommand
      cmd: "cd (^fd --type d --hidden --follow --exclude .git | ^fzf --height 40% --reverse | str trim | if ($in | is-empty) { '.' } else { $in })"
    }
  }
]

# Prompt selection (oh-my-posh vs plain) lives in autoload/10-prompt.nu, which
# loads after the oh-my-posh init script in vendor/autoload.

# mise (generated as a Nushell module by env.nu; must be loaded with `use`,
# not `source` / vendor/autoload, because it exports `main`).
const MISE_MODULE = ($nu.data-dir | path join "mise.nu")
use (if ($MISE_MODULE | path exists) { $MISE_MODULE } else { null })

# Machine-specific overrides (equivalent of ~/.zshrc.local).
const LOCAL_CONFIG = ($nu.default-config-dir | path join "local.nu")
source (if ($LOCAL_CONFIG | path exists) { $LOCAL_CONFIG } else { null })
