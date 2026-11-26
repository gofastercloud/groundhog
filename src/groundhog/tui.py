"""Interactive stdlib curses TUI for Groundhog."""

from __future__ import annotations

import contextlib
import curses
from collections.abc import Callable
from dataclasses import dataclass

from groundhog import __version__
from groundhog.config import GroundhogPaths
from groundhog.ops import (
    StatusSummary,
    cmd_ansible,
    cmd_brew,
    cmd_capture,
    cmd_diff,
    cmd_init_custom,
    cmd_link,
    cmd_status,
    cmd_verify_custom,
    collect_status,
)


@dataclass(frozen=True)
class MenuItem:
    """One selectable action in the Groundhog TUI."""

    key: str
    title: str
    description: str
    action: Callable[[GroundhogPaths], int] | None


def build_menu_items() -> list[MenuItem]:
    """Return the ordered TUI menu items."""
    return [
        MenuItem(
            key="ansible",
            title="Apply Playbook (Ansible)",
            description="Run full macOS setup with single-auth sudo keepalive",
            action=lambda p: cmd_ansible(p, []),
        ),
        MenuItem(
            key="check",
            title="Dry-Run Playbook (--check --diff)",
            description="Preview Ansible changes without modifying the system",
            action=lambda p: cmd_ansible(p, [], check=True),
        ),
        MenuItem(
            key="link",
            title="Link Dotfiles & Hooks",
            description="Stow configs, link custom overlay, install hooks, update tmux/bat",
            action=lambda p: cmd_link(p),
        ),
        MenuItem(
            key="status",
            title="Show Status",
            description="Inspect Stow packages, custom links, app copies, and Homebrew",
            action=lambda p: cmd_status(p),
        ),
        MenuItem(
            key="diff",
            title="Diff Live vs Repo",
            description="Show unified diffs between $HOME and Groundhog configs",
            action=lambda p: cmd_diff(p),
        ),
        MenuItem(
            key="brew",
            title="Sync Brewfiles",
            description="Install packages from core, custom/Brewfile, and .Brewfile.local",
            action=lambda p: cmd_brew(p),
        ),
        MenuItem(
            key="capture",
            title="Capture App-Managed Copies",
            description="Copy updated files from custom/copies.conf back into custom/",
            action=lambda p: cmd_capture(p),
        ),
        MenuItem(
            key="verify-custom",
            title="Verify Custom Overlay",
            description="Validate custom/ YAML, manifests, SSH keys, and git hooks",
            action=lambda p: cmd_verify_custom(p),
        ),
        MenuItem(
            key="init-custom",
            title="Initialise Custom Overlay",
            description="Scaffold a private overlay repository in custom/",
            action=lambda p: cmd_init_custom(p),
        ),
        MenuItem(
            key="quit",
            title="Quit",
            description="Exit Groundhog",
            action=None,
        ),
    ]


class MenuState:
    """Headless cursor/selection state for the TUI (unit-testable without a TTY)."""

    def __init__(self, items: list[MenuItem]) -> None:
        self.items = items
        self.index = 0

    def move(self, delta: int) -> None:
        if not self.items:
            return
        self.index = (self.index + delta) % len(self.items)

    @property
    def current(self) -> MenuItem:
        return self.items[self.index]


def _init_colours() -> None:
    if not curses.has_colors():
        return
    curses.start_color()
    curses.use_default_colors()
    # Pair 1: header accent, 2: ok green, 3: warn yellow, 4: highlight row, 5: dim text
    curses.init_pair(1, curses.COLOR_MAGENTA, -1)
    curses.init_pair(2, curses.COLOR_GREEN, -1)
    curses.init_pair(3, curses.COLOR_YELLOW, -1)
    curses.init_pair(4, curses.COLOR_BLACK, curses.COLOR_CYAN)
    curses.init_pair(5, curses.COLOR_CYAN, -1)


def _safe_addstr(win: curses.window, y: int, x: int, text: str, attr: int = 0) -> None:
    max_y, max_x = win.getmaxyx()
    if y < 0 or y >= max_y or x >= max_x:
        return
    clipped = text[: max(0, max_x - x - 1)]
    with contextlib.suppress(curses.error):
        win.addstr(y, x, clipped, attr)


def _draw_screen(
    stdscr: curses.window,
    paths: GroundhogPaths,
    state: MenuState,
    summary: StatusSummary,
    last_message: str,
) -> None:
    stdscr.erase()
    max_y, max_x = stdscr.getmaxyx()
    accent = curses.color_pair(1) | curses.A_BOLD if curses.has_colors() else curses.A_BOLD
    ok_attr = curses.color_pair(2) if curses.has_colors() else curses.A_NORMAL
    warn_attr = curses.color_pair(3) if curses.has_colors() else curses.A_NORMAL
    sel_attr = curses.color_pair(4) | curses.A_BOLD if curses.has_colors() else curses.A_REVERSE
    hint_attr = curses.color_pair(5) if curses.has_colors() else curses.A_DIM

    _safe_addstr(stdscr, 1, 2, f"GROUNDHOG  v{__version__}", accent)
    _safe_addstr(stdscr, 2, 2, f"Repo:    {paths.repo_dir}", curses.A_DIM)
    overlay_text = "active (custom/)" if summary.custom_present else "none (run init-custom)"
    _safe_addstr(
        stdscr,
        3,
        2,
        f"Overlay: {overlay_text}",
        ok_attr if summary.custom_present else warn_attr,
    )
    stow_ok = summary.stowed_ok == summary.stowed_total
    links_ok = summary.links_ok == summary.links_total
    _safe_addstr(
        stdscr,
        4,
        2,
        f"Status:  stowed {summary.stowed_ok}/{summary.stowed_total}  |  "
        f"links {summary.links_ok}/{summary.links_total}  |  "
        f"copies {summary.copies_ok}/{summary.copies_total}",
        ok_attr if (stow_ok and links_ok) else warn_attr,
    )

    divider = "─" * max(10, min(max_x - 4, 72))
    _safe_addstr(stdscr, 5, 2, divider, curses.A_DIM)

    start_y = 7
    for idx, item in enumerate(state.items):
        row_y = start_y + idx
        if row_y >= max_y - 4:
            break
        marker = "❯ " if idx == state.index else "  "
        line = f"{marker}{item.title:<34}  {item.description}"
        _safe_addstr(stdscr, row_y, 2, line, sel_attr if idx == state.index else curses.A_NORMAL)

    if last_message and max_y > 6:
        _safe_addstr(stdscr, max_y - 3, 2, last_message, hint_attr)

    footer = "↑/↓ or j/k: move   Enter: run   r: refresh   q: quit"
    _safe_addstr(stdscr, max_y - 1, 2, footer, curses.A_DIM)
    stdscr.refresh()


def _tui_main(stdscr: curses.window, paths: GroundhogPaths) -> int:
    with contextlib.suppress(curses.error):
        curses.curs_set(0)
    stdscr.keypad(True)
    _init_colours()

    state = MenuState(build_menu_items())
    summary = collect_status(paths, include_brew=False)
    last_message = ""

    while True:
        _draw_screen(stdscr, paths, state, summary, last_message)
        ch = stdscr.getch()
        if ch in (ord("q"), ord("Q"), 27):
            return 0
        if ch in (curses.KEY_UP, ord("k")):
            state.move(-1)
        elif ch in (curses.KEY_DOWN, ord("j")):
            state.move(1)
        elif ch in (ord("r"), ord("R")):
            summary = collect_status(paths, include_brew=False)
            last_message = "Status refreshed."
        elif ch in (curses.KEY_ENTER, 10, 13):
            selected = state.current
            if selected.action is None:
                return 0
            curses.def_prog_mode()
            curses.endwin()
            try:
                rc = selected.action(paths)
                print()
                input("Press Enter to return to Groundhog...")
                last_message = f"Last action '{selected.key}' exited with code {rc}."
            except KeyboardInterrupt:
                last_message = f"Action '{selected.key}' interrupted."
            finally:
                curses.reset_prog_mode()
                stdscr.refresh()
                summary = collect_status(paths, include_brew=False)


def run_tui(paths: GroundhogPaths) -> int:
    """Launch the interactive curses TUI."""
    return curses.wrapper(_tui_main, paths)
