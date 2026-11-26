"""Repo-scoped GitHub App broker and signing wrappers for autonomous agents.

Keeps the user's hardware-bound Secretive keys untouched while allowing agents to:
  1. Sign every commit locally with a dedicated, revocable signing-only SSH key
     (producing Verified commits via a zero-privilege GitHub machine user).
  2. Push feature branches (`agent/*`) and call the GitHub API (`gh`) using
     short-lived (1-hour), single-repository GitHub App installation tokens.
  3. Enforce local guardrails (no direct pushes to main/master, branch prefix
     enforcement, and human-review merge blocks) alongside GitHub Rulesets.

Stdlib-only (uses macOS `/usr/bin/openssl` for RS256 JWT signing and
`/usr/bin/security` for Keychain storage, with an env-var PEM override for
future Linux/cloud portability).
"""

from __future__ import annotations

import base64
import contextlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import TextIO

from groundhog.config import GroundhogPaths, expand_home

DEFAULT_CONFIG_REL = Path(".config") / "groundhog" / "agent-git.json"
DEFAULT_KEYCHAIN_SERVICE = "groundhog-agent-git-app-key"
KEYCHAIN_ACCOUNT = "groundhog"
PROTECTED_BRANCHES = frozenset({"main", "master"})

_GITHUB_REMOTE_PATTERNS = (
    re.compile(r"^git@github\.com:([^/]+/[^/]+?)(?:\.git)?$"),
    re.compile(r"^https?://(?:[^@]+@)?github\.com/([^/]+/[^/]+?)(?:\.git)?/?$"),
    re.compile(r"^ssh://git@github\.com/([^/]+/[^/]+?)(?:\.git)?/?$"),
)


@dataclass(frozen=True)
class AgentGitConfig:
    """Loaded configuration for Groundhog's agent-git broker."""

    app_id: str
    installation_id: str
    bot_name: str
    bot_email: str
    signing_key: Path
    default_agent_name: str = "Groundhog Agent"
    keychain_service: str = DEFAULT_KEYCHAIN_SERVICE
    allowed_branch_prefix: str = "agent/"
    repo_policies: dict[str, str] = field(default_factory=dict)

    @classmethod
    def load(cls, paths: GroundhogPaths) -> AgentGitConfig:
        env_path = os.environ.get("GROUNDHOG_AGENT_GIT_CONFIG")
        cfg_path = (
            Path(env_path).expanduser() if env_path else (paths.home_dir / DEFAULT_CONFIG_REL)
        )
        if not cfg_path.is_file():
            raise FileNotFoundError(
                f"Agent Git config not found at {cfg_path}. "
                "Enable agent_git_enabled in custom/config.yml and run "
                "`./groundhog ansible --tags agent-git`."
            )
        raw = json.loads(cfg_path.read_text(encoding="utf-8"))
        required = ("app_id", "installation_id", "bot_name", "bot_email", "signing_key")
        missing = [k for k in required if not str(raw.get(k, "")).strip()]
        if missing:
            raise ValueError(f"{cfg_path} is missing required fields: {', '.join(missing)}")
        policies_raw = raw.get("repo_policies") or {}
        policies = {str(k).lower(): str(v) for k, v in policies_raw.items()}
        return cls(
            app_id=str(raw["app_id"]).strip(),
            installation_id=str(raw["installation_id"]).strip(),
            bot_name=str(raw["bot_name"]).strip(),
            bot_email=str(raw["bot_email"]).strip(),
            signing_key=expand_home(str(raw["signing_key"]).strip(), paths.home_dir),
            default_agent_name=str(raw.get("default_agent_name") or "Groundhog Agent").strip(),
            keychain_service=str(raw.get("keychain_service") or DEFAULT_KEYCHAIN_SERVICE).strip(),
            allowed_branch_prefix=str(raw.get("allowed_branch_prefix") or "agent/").strip(),
            repo_policies=policies,
        )


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def parse_github_repo(remote_url: str) -> str | None:
    """Extract `owner/repo` from a GitHub SSH or HTTPS remote URL."""
    cleaned = remote_url.strip()
    for pat in _GITHUB_REMOTE_PATTERNS:
        m = pat.match(cleaned)
        if m:
            return m.group(1)
    return None


def parse_github_path(path_value: str) -> str | None:
    """Extract `owner/repo` from a git-credential `path` field."""
    cleaned = path_value.strip().lstrip("/")
    if cleaned.endswith(".git"):
        cleaned = cleaned[:-4]
    parts = [p for p in cleaned.split("/") if p]
    if len(parts) >= 2:
        return f"{parts[0]}/{parts[1]}"
    return None


def create_app_jwt(app_id: str, pem_bytes: bytes, *, now: int | None = None) -> str:
    """Create an RS256 GitHub App JWT using stdlib + system `openssl`."""
    ts = int(time.time()) if now is None else now
    header = _b64url(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = _b64url(
        json.dumps(
            {"iat": ts - 60, "exp": ts + 540, "iss": str(app_id)},
            separators=(",", ":"),
        ).encode()
    )
    signing_input = f"{header}.{payload}".encode("ascii")

    openssl = shutil.which("openssl") or "/usr/bin/openssl"
    with tempfile.TemporaryDirectory(prefix="groundhog-jwt-") as tmp_dir:
        key_path = Path(tmp_dir) / "app.pem"
        fd = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            os.write(fd, pem_bytes)
        finally:
            os.close(fd)
        proc = subprocess.run(
            [openssl, "dgst", "-sha256", "-sign", str(key_path)],
            input=signing_input,
            capture_output=True,
            check=False,
        )
        if proc.returncode != 0:
            detail = proc.stderr.decode("utf-8", errors="replace").strip()
            raise RuntimeError(f"openssl JWT signing failed: {detail}")
        signature = _b64url(proc.stdout)
    return f"{header}.{payload}.{signature}"


def store_app_key(pem_path: Path, service: str = DEFAULT_KEYCHAIN_SERVICE) -> None:
    """Import a GitHub App PEM private key into macOS Keychain."""
    if not pem_path.is_file():
        raise FileNotFoundError(f"PEM file not found: {pem_path}")
    pem_text = pem_path.read_text(encoding="utf-8").strip()
    if "PRIVATE KEY-----" not in pem_text:
        raise ValueError(f"{pem_path} does not look like a PEM private key")
    # Store base64-encoded PEM so multiline newlines survive macOS `security` CLI cleanly.
    encoded = base64.b64encode(pem_text.encode("utf-8")).decode("ascii")
    proc = subprocess.run(
        [
            "/usr/bin/security",
            "add-generic-password",
            "-U",
            "-s",
            service,
            "-a",
            KEYCHAIN_ACCOUNT,
            "-w",
            encoded,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"Failed to store key in macOS Keychain: {proc.stderr.strip()}")


def load_app_key(config: AgentGitConfig) -> bytes:
    """Load the GitHub App PEM private key from env override or macOS Keychain."""
    pem_override = os.environ.get("GROUNDHOG_AGENT_GIT_PEM_FILE")
    if pem_override:
        return Path(pem_override).expanduser().read_bytes()

    proc = subprocess.run(
        [
            "/usr/bin/security",
            "find-generic-password",
            "-s",
            config.keychain_service,
            "-a",
            KEYCHAIN_ACCOUNT,
            "-w",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"Could not read GitHub App key from Keychain service '{config.keychain_service}'. "
            "Import it with: groundhog agent-git store-key /path/to/private-key.pem"
        )
    raw = proc.stdout.strip()
    if "PRIVATE KEY-----" in raw:
        return raw.encode("utf-8")
    return base64.b64decode(raw)


def mint_repo_token(config: AgentGitConfig, repo_slug: str) -> str:
    """Mint a 1-hour GitHub App installation token scoped strictly to `repo_slug`."""
    if "/" not in repo_slug:
        raise ValueError(f"Expected 'owner/repo', got {repo_slug!r}")
    repo_name = repo_slug.split("/", 1)[1]
    jwt_token = create_app_jwt(config.app_id, load_app_key(config))
    url = f"https://api.github.com/app/installations/{config.installation_id}/access_tokens"
    body = json.dumps({"repositories": [repo_name]}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {jwt_token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
            "User-Agent": "groundhog-agent-git",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace").strip()
        raise RuntimeError(
            f"GitHub token mint failed for {repo_slug} (HTTP {exc.code}): {detail}"
        ) from exc
    token = data.get("token")
    if not isinstance(token, str) or not token:
        raise RuntimeError(f"GitHub API response missing token for {repo_slug}")
    return token


def _git_output(args: list[str], cwd: Path) -> str:
    proc = subprocess.run(
        ["git", *args],
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or f"git {' '.join(args)} failed")
    return proc.stdout.strip()


def detect_current_repo(cwd: Path) -> str:
    remote = _git_output(["remote", "get-url", "origin"], cwd)
    slug = parse_github_repo(remote)
    if not slug:
        raise RuntimeError(f"Origin remote is not a GitHub repo: {remote!r}")
    return slug


def detect_current_branch(cwd: Path) -> str:
    return _git_output(["rev-parse", "--abbrev-ref", "HEAD"], cwd)


def validate_push_args(
    git_args: list[str],
    *,
    current_branch: str,
    allowed_prefix: str = "agent/",
) -> str | None:
    """Return an error message if a `git push` violates agent branch guardrails."""
    if not git_args or git_args[0] != "push":
        return None

    push_tokens = git_args[1:]
    positional: list[str] = []
    skip_next = False
    for tok in push_tokens:
        if skip_next:
            skip_next = False
            continue
        if tok in {"-o", "--push-option", "--receive-pack", "--exec", "--repo"}:
            skip_next = True
            continue
        if tok.startswith("-"):
            continue
        positional.append(tok)

    # First positional is remote (if present); remaining are refspecs.
    refspecs = positional[1:] if len(positional) >= 2 else []
    target_branches: list[str] = []
    if not refspecs:
        target_branches.append(current_branch)
    else:
        for spec in refspecs:
            dest = spec.split(":", 1)[1] if ":" in spec else spec
            dest = dest.lstrip("+")
            if dest.startswith("refs/heads/"):
                dest = dest[len("refs/heads/") :]
            if dest == "HEAD" or not dest:
                target_branches.append(current_branch)
            else:
                target_branches.append(dest)

    for branch in target_branches:
        if branch in PROTECTED_BRANCHES:
            return (
                f"Blocked: agent-git refuses direct pushes to protected branch '{branch}'. "
                f"Create a '{allowed_prefix}<persona>/<task>' branch and open a PR instead."
            )
        if allowed_prefix and not branch.startswith(allowed_prefix):
            return (
                f"Blocked: agent-git only pushes branches prefixed with '{allowed_prefix}' "
                f"(got '{branch}')."
            )
    return None


def validate_gh_args(
    gh_args: list[str],
    *,
    repo_slug: str,
    repo_policies: dict[str, str],
) -> str | None:
    """Return an error message if a `gh` command violates local repo merge policy."""
    non_flags = [tok for tok in gh_args if not tok.startswith("-")]
    if len(non_flags) >= 2 and non_flags[0] == "pr" and non_flags[1] == "merge":
        policy = repo_policies.get(repo_slug.lower(), "autonomous")
        if policy == "human-review":
            return (
                f"Blocked: '{repo_slug}' requires human approval before merging "
                "(repo_policies = 'human-review'). Leave the PR open with label "
                "'needs-human-review' for Dave to approve and merge."
            )
    return None


def build_agent_git_command(
    paths: GroundhogPaths,
    config: AgentGitConfig,
    git_args: list[str],
    *,
    agent_name: str | None = None,
) -> tuple[list[str], dict[str, str]]:
    """Build the `git` argv and environment for an agent-signed, broker-authenticated run."""
    groundhog_bin = str(paths.launcher_script)
    cred_helper = f"!{groundhog_bin} agent-git credential"
    cmd = [
        "git",
        "-c",
        "gpg.format=ssh",
        "-c",
        f"user.signingkey={config.signing_key}",
        "-c",
        "commit.gpgsign=true",
        "-c",
        "url.https://github.com/.insteadOf=git@github.com:",
        "-c",
        "credential.useHttpPath=true",
        "-c",
        "credential.helper=",
        "-c",
        f"credential.helper={cred_helper}",
        *git_args,
    ]
    resolved_author = agent_name or os.environ.get("AGENT_NAME") or config.default_agent_name
    env = os.environ.copy()
    env["GIT_COMMITTER_NAME"] = config.bot_name
    env["GIT_COMMITTER_EMAIL"] = config.bot_email
    env["GIT_AUTHOR_NAME"] = resolved_author
    env["GIT_AUTHOR_EMAIL"] = config.bot_email
    env["GIT_TERMINAL_PROMPT"] = "0"
    return cmd, env


def _extract_repo_flag(args: list[str]) -> str | None:
    for i, tok in enumerate(args):
        if tok in {"-R", "--repo"} and i + 1 < len(args):
            return args[i + 1]
        if tok.startswith("--repo="):
            return tok.split("=", 1)[1]
    return None


def cmd_credential(
    config: AgentGitConfig,
    action: str,
    *,
    stdin: TextIO | None = None,
    out: TextIO | None = None,
) -> int:
    """Handle the Git credential helper protocol (`get`, `store`, `erase`)."""
    if action != "get":
        return 0
    stream_in = stdin or sys.stdin
    stream_out = out or sys.stdout

    attrs: dict[str, str] = {}
    for line in stream_in.read().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            attrs[k.strip()] = v.strip()

    if attrs.get("host") != "github.com":
        return 0
    slug = parse_github_path(attrs.get("path", ""))
    if not slug:
        return 0
    token = mint_repo_token(config, slug)
    print("protocol=https", file=stream_out)
    print("host=github.com", file=stream_out)
    print("username=x-access-token", file=stream_out)
    print(f"password={token}", file=stream_out)
    return 0


def cmd_agent_git(
    paths: GroundhogPaths,
    argv: list[str],
    *,
    out: TextIO | None = None,
    err: TextIO | None = None,
) -> int:
    """Entry point for `groundhog agent-git <subcommand>`."""
    out = out or sys.stdout
    err = err or sys.stderr

    if not argv or argv[0] in {"-h", "--help"}:
        print(
            "Usage: groundhog agent-git <subcommand> [args...]\n\n"
            "Subcommands:\n"
            "  store-key <pem-file>       Import GitHub App private key into macOS Keychain\n"
            "  token --repo <owner/repo>  Mint a 1-hour single-repo installation token\n"
            "  credential <action>        Git credential helper (get/store/erase)\n"
            "  git <git-args...>          Run git with agent signing key & 1-hour App token\n"
            "  gh <gh-args...>            Run gh with 1-hour single-repo App token\n"
            "  status                     Show agent-git configuration and readiness",
            file=out,
        )
        return 0

    sub = argv[0]
    rest = argv[1:]

    try:
        if sub == "store-key":
            if len(rest) != 1:
                print("Usage: groundhog agent-git store-key <path-to-private-key.pem>", file=err)
                return 2
            service = DEFAULT_KEYCHAIN_SERVICE
            with contextlib.suppress(FileNotFoundError, ValueError):
                service = AgentGitConfig.load(paths).keychain_service
            pem_path = Path(rest[0]).expanduser()
            store_app_key(pem_path, service=service)
            print(f"Stored GitHub App private key in Keychain service '{service}'.", file=out)
            print(f"You can now securely delete {pem_path}.", file=out)
            return 0

        config = AgentGitConfig.load(paths)

        if sub == "status":
            print(f"App ID:          {config.app_id}", file=out)
            print(f"Installation ID: {config.installation_id}", file=out)
            print(f"Bot committer:   {config.bot_name} <{config.bot_email}>", file=out)
            print(f"Default author:  {config.default_agent_name}", file=out)
            print(
                f"Signing key:     {config.signing_key} "
                f"({'present' if config.signing_key.is_file() else 'MISSING'})",
                file=out,
            )
            print(f"Branch prefix:   {config.allowed_branch_prefix}", file=out)
            try:
                load_app_key(config)
                print(f"Keychain key:    present ({config.keychain_service})", file=out)
            except RuntimeError:
                print(f"Keychain key:    MISSING ({config.keychain_service})", file=out)
            if config.repo_policies:
                print("Repo policies:", file=out)
                for repo, policy in sorted(config.repo_policies.items()):
                    print(f"  {repo}: {policy}", file=out)
            return 0

        if sub == "token":
            repo = _extract_repo_flag(rest)
            if not repo:
                repo = detect_current_repo(Path.cwd())
            print(mint_repo_token(config, repo), file=out)
            return 0

        if sub == "credential":
            action = rest[0] if rest else "get"
            return cmd_credential(config, action, out=out)

        if sub == "git":
            if not rest:
                print("Usage: groundhog agent-git git <git-args...>", file=err)
                return 2
            cwd = Path.cwd()
            if rest[0] == "push":
                branch = detect_current_branch(cwd)
                blocked = validate_push_args(
                    rest,
                    current_branch=branch,
                    allowed_prefix=config.allowed_branch_prefix,
                )
                if blocked:
                    print(blocked, file=err)
                    return 1
            cmd, env = build_agent_git_command(paths, config, rest)
            proc = subprocess.run(cmd, cwd=cwd, env=env, check=False)
            return proc.returncode

        if sub == "gh":
            if not rest:
                print("Usage: groundhog agent-git gh <gh-args...>", file=err)
                return 2
            cwd = Path.cwd()
            repo = _extract_repo_flag(rest) or detect_current_repo(cwd)
            blocked = validate_gh_args(rest, repo_slug=repo, repo_policies=config.repo_policies)
            if blocked:
                print(blocked, file=err)
                return 1
            token = mint_repo_token(config, repo)
            env = os.environ.copy()
            env["GH_TOKEN"] = token
            env.pop("GITHUB_TOKEN", None)
            proc = subprocess.run(["gh", *rest], cwd=cwd, env=env, check=False)
            return proc.returncode

        print(f"Unknown agent-git subcommand: {sub}", file=err)
        return 2
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        print(f"Error: {exc}", file=err)
        return 1
