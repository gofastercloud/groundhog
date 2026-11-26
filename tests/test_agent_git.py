"""Unit tests for Groundhog's repo-scoped agent-git GitHub App broker."""

from __future__ import annotations

import base64
import io
import json
import shutil
import subprocess
from pathlib import Path

import pytest

from groundhog.agent_git import (
    AgentGitConfig,
    build_agent_git_command,
    cmd_agent_git,
    cmd_credential,
    create_app_jwt,
    parse_github_path,
    parse_github_repo,
    validate_gh_args,
    validate_push_args,
)
from groundhog.config import GroundhogPaths


def _sample_config(tmp_path: Path) -> AgentGitConfig:
    return AgentGitConfig(
        app_id="123456",
        installation_id="987654",
        bot_name="example-bot",
        bot_email="12345+example-bot@users.noreply.github.com",
        signing_key=tmp_path / ".ssh" / "id_agent_sign.pub",
        default_agent_name="Groundhog Agent",
        allowed_branch_prefix="agent/",
        repo_policies={"acme/protected-repo": "human-review"},
    )


def test_parse_github_repo_and_path() -> None:
    assert parse_github_repo("git@github.com:acme/widget.git") == "acme/widget"
    assert parse_github_repo("https://github.com/acme/widget.git") == "acme/widget"
    assert parse_github_repo("https://x-access-token@github.com/acme/widget") == "acme/widget"
    assert parse_github_repo("ssh://git@github.com/acme/widget.git") == "acme/widget"
    assert parse_github_repo("https://gitlab.com/acme/widget.git") is None

    assert parse_github_path("acme/widget.git") == "acme/widget"
    assert parse_github_path("/acme/widget") == "acme/widget"
    assert parse_github_path("just-owner") is None


def test_validate_push_args_blocks_protected_and_non_agent_branches() -> None:
    assert validate_push_args(["push"], current_branch="main") is not None
    assert validate_push_args(["push", "origin", "master"], current_branch="agent/a/b") is not None
    assert (
        validate_push_args(["push", "origin", "HEAD:main"], current_branch="agent/a/b") is not None
    )
    assert validate_push_args(["push", "-u", "origin", "feat/foo"], current_branch="feat/foo")

    assert (
        validate_push_args(["push", "-u", "origin", "agent/codex/fix-1"], current_branch="main")
        is None
    )
    assert validate_push_args(["push"], current_branch="agent/codex/fix-1") is None
    assert validate_push_args(["status"], current_branch="main") is None


def test_validate_gh_args_enforces_human_review_policy() -> None:
    policies = {"acme/gated": "human-review", "acme/auto": "autonomous"}
    assert validate_gh_args(
        ["pr", "merge", "--squash"], repo_slug="acme/gated", repo_policies=policies
    )
    assert (
        validate_gh_args(["pr", "create", "--fill"], repo_slug="acme/gated", repo_policies=policies)
        is None
    )
    assert (
        validate_gh_args(["pr", "merge", "--squash"], repo_slug="acme/auto", repo_policies=policies)
        is None
    )


@pytest.mark.skipif(not shutil.which("openssl"), reason="openssl not installed")
def test_create_app_jwt_produces_verifiable_rs256_signature(tmp_path: Path) -> None:
    key_path = tmp_path / "app.pem"
    pub_path = tmp_path / "app.pub.pem"
    subprocess.run(
        ["openssl", "genrsa", "-out", str(key_path), "2048"],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        ["openssl", "rsa", "-in", str(key_path), "-pubout", "-out", str(pub_path)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    token = create_app_jwt("424242", key_path.read_bytes(), now=1_700_000_000)
    header_b64, payload_b64, sig_b64 = token.split(".")

    def _decode_json(seg: str) -> dict[str, object]:
        padded = seg + "=" * (-len(seg) % 4)
        return json.loads(base64.urlsafe_b64decode(padded))

    assert _decode_json(header_b64) == {"alg": "RS256", "typ": "JWT"}
    assert _decode_json(payload_b64) == {
        "iat": 1_699_999_940,
        "exp": 1_700_000_540,
        "iss": "424242",
    }

    sig_path = tmp_path / "sig.bin"
    sig_path.write_bytes(base64.urlsafe_b64decode(sig_b64 + "=" * (-len(sig_b64) % 4)))
    verify = subprocess.run(
        ["openssl", "dgst", "-sha256", "-verify", str(pub_path), "-signature", str(sig_path)],
        input=f"{header_b64}.{payload_b64}".encode("ascii"),
        capture_output=True,
        check=False,
    )
    assert verify.returncode == 0, verify.stderr.decode()


def test_credential_helper_emits_single_repo_token(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cfg = _sample_config(tmp_path)
    requested: list[str] = []

    def fake_mint(_cfg: AgentGitConfig, slug: str) -> str:
        requested.append(slug)
        return "ghs_test_token_123"

    monkeypatch.setattr("groundhog.agent_git.mint_repo_token", fake_mint)

    out = io.StringIO()
    rc = cmd_credential(
        cfg,
        "get",
        stdin=io.StringIO("protocol=https\nhost=github.com\npath=acme/widget.git\n\n"),
        out=out,
    )
    assert rc == 0
    assert requested == ["acme/widget"]
    assert "username=x-access-token\n" in out.getvalue()
    assert "password=ghs_test_token_123\n" in out.getvalue()


def test_build_agent_git_command_isolates_signing_and_credentials(tmp_path: Path) -> None:
    paths = GroundhogPaths(repo_dir=tmp_path / "groundhog", home_dir=tmp_path)
    cfg = _sample_config(tmp_path)
    cmd, env = build_agent_git_command(paths, cfg, ["commit", "-m", "test"], agent_name="Codex")

    assert "gpg.format=ssh" in cmd
    assert f"user.signingkey={cfg.signing_key}" in cmd
    assert "commit.gpgsign=true" in cmd
    assert "url.https://github.com/.insteadOf=git@github.com:" in cmd
    assert "credential.useHttpPath=true" in cmd
    assert "credential.helper=" in cmd
    assert f"credential.helper=!{paths.launcher_script} agent-git credential" in cmd
    assert env["GIT_COMMITTER_NAME"] == "example-bot"
    assert env["GIT_COMMITTER_EMAIL"] == cfg.bot_email
    assert env["GIT_AUTHOR_NAME"] == "Codex"
    assert env["GIT_AUTHOR_EMAIL"] == cfg.bot_email


def test_cmd_agent_git_status_reads_config(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    cfg_dir = tmp_path / ".config" / "groundhog"
    cfg_dir.mkdir(parents=True)
    key_file = tmp_path / ".ssh" / "id_agent_sign.pub"
    key_file.parent.mkdir(parents=True)
    key_file.write_text("ssh-ed25519 AAAA test\n", encoding="utf-8")
    (cfg_dir / "agent-git.json").write_text(
        json.dumps(
            {
                "app_id": "12345",
                "installation_id": "67890",
                "bot_name": "example-bot",
                "bot_email": "123+example-bot@users.noreply.github.com",
                "signing_key": "~/.ssh/id_agent_sign.pub",
                "repo_policies": {"acme/gated": "human-review"},
            }
        ),
        encoding="utf-8",
    )
    pem_file = tmp_path / "dummy.pem"
    pem_file.write_text("-----BEGIN RSA PRIVATE KEY-----\ndummy\n-----END RSA PRIVATE KEY-----\n")
    monkeypatch.setenv("GROUNDHOG_AGENT_GIT_PEM_FILE", str(pem_file))

    paths = GroundhogPaths(repo_dir=tmp_path, home_dir=tmp_path)
    out = io.StringIO()
    rc = cmd_agent_git(paths, ["status"], out=out, err=io.StringIO())
    assert rc == 0
    text = out.getvalue()
    assert "App ID:          12345" in text
    assert "Signing key:" in text and "(present)" in text
    assert "Keychain key:    present" in text
    assert "acme/gated: human-review" in text
