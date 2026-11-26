# Prompt selection. Loads after vendor/autoload/oh-my-posh.nu (vendor dirs
# come first), so this can override the prompt oh-my-posh just installed.
# The generated init script is the same for every terminal; only this file
# decides whether to keep it.

if ($env.MOBILE? | is-not-empty) {
  # Mobile clients (Prompt 3 on iOS) set MOBILE=1 and lack Nerd Font glyphs:
  # plain user@host:path prompt, mirroring .zshrc.
  let host = (sys host | get hostname | split row "." | first)
  $env.PROMPT_COMMAND = {|| $"($env.USER)@($host):($env.PWD | str replace $env.HOME '~') " }
  $env.PROMPT_COMMAND_RIGHT = ""
  $env.PROMPT_INDICATOR = ""
  $env.PROMPT_MULTILINE_INDICATOR = "::: "
} else if ($env.TERM_PROGRAM? == "Apple_Terminal") {
  # Apple Terminal renders oh-my-posh badly: fall back to nu's built-in prompt.
  hide-env --ignore-errors PROMPT_COMMAND PROMPT_COMMAND_RIGHT PROMPT_INDICATOR PROMPT_MULTILINE_INDICATOR
  $env.config.render_right_prompt_on_last_line = false
}
