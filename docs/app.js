// Groundhog interactive site — Three.js Catppuccin Mocha backdrop + animated CLI walkthroughs.

const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/* ── 1. Three.js 3D Backdrop (Time-Loop Torus + Orbiting GNU Stow Cubes) ── */
async function initThreeScene() {
  if (prefersReducedMotion) return;
  const canvas = document.getElementById('bg-canvas');
  if (!canvas) return;

  try {
    const THREE = await import('three');

    const renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(window.innerWidth, window.innerHeight);

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(52, window.innerWidth / window.innerHeight, 0.1, 100);
    camera.position.z = 16;

    const root = new THREE.Group();
    scene.add(root);

    // Subtle glowing Groundhog Day time-loop torus
    const torusGeo = new THREE.TorusGeometry(6.2, 0.045, 16, 120);
    const torusMat = new THREE.MeshBasicMaterial({
      color: 0x94e2d5,
      transparent: true,
      opacity: 0.28,
    });
    const torus = new THREE.Mesh(torusGeo, torusMat);
    torus.rotation.x = 0.65;
    torus.rotation.y = -0.35;
    root.add(torus);

    // Secondary lavender orbital ring
    const ringGeo = new THREE.TorusGeometry(8.1, 0.025, 12, 120);
    const ringMat = new THREE.MeshBasicMaterial({
      color: 0xb4befe,
      transparent: true,
      opacity: 0.16,
    });
    const ring = new THREE.Mesh(ringGeo, ringMat);
    ring.rotation.x = 1.15;
    ring.rotation.y = 0.4;
    root.add(ring);

    // Floating isometric GNU Stow cubes
    const cubeColors = [0xb4befe, 0xcba6f7, 0x94e2d5, 0xfab387, 0x89dceb, 0xa6e3a1];
    const cubes = [];
    const cubeGeo = new THREE.BoxGeometry(0.75, 0.75, 0.75);
    const edgeGeo = new THREE.EdgesGeometry(cubeGeo);

    cubeColors.forEach((hex, idx) => {
      const group = new THREE.Group();
      const fill = new THREE.Mesh(
        cubeGeo,
        new THREE.MeshBasicMaterial({ color: hex, transparent: true, opacity: 0.14 })
      );
      const wire = new THREE.LineSegments(
        edgeGeo,
        new THREE.LineBasicMaterial({ color: hex, transparent: true, opacity: 0.6 })
      );
      group.add(fill, wire);

      const angle = (idx / cubeColors.length) * Math.PI * 2;
      const radius = 5.4 + (idx % 2) * 2.2;
      group.userData = {
        angle,
        radius,
        speed: 0.14 + (idx % 3) * 0.05,
        yOffset: (idx - 2.5) * 0.9,
      };
      root.add(group);
      cubes.push(group);
    });

    // Catppuccin starfield particles
    const starCount = 260;
    const positions = new Float32Array(starCount * 3);
    for (let i = 0; i < starCount; i++) {
      positions[i * 3] = (Math.random() - 0.5) * 38;
      positions[i * 3 + 1] = (Math.random() - 0.5) * 28;
      positions[i * 3 + 2] = (Math.random() - 0.5) * 22 - 4;
    }
    const starGeo = new THREE.BufferGeometry();
    starGeo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    const starMat = new THREE.PointsMaterial({
      color: 0xb4befe,
      size: 0.075,
      transparent: true,
      opacity: 0.45,
    });
    const stars = new THREE.Points(starGeo, starMat);
    scene.add(stars);

    let mouseX = 0;
    let mouseY = 0;
    window.addEventListener('pointermove', (e) => {
      mouseX = (e.clientX / window.innerWidth - 0.5) * 1.4;
      mouseY = (e.clientY / window.innerHeight - 0.5) * 1.0;
    }, { passive: true });

    window.addEventListener('resize', () => {
      camera.aspect = window.innerWidth / window.innerHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(window.innerWidth, window.innerHeight);
    });

    const clock = new THREE.Clock();
    function animate() {
      requestAnimationFrame(animate);
      const t = clock.getElapsedTime();

      root.rotation.y += (mouseX * 0.35 - root.rotation.y) * 0.03;
      root.rotation.x += (mouseY * 0.25 - root.rotation.x) * 0.03;

      torus.rotation.z = t * 0.16;
      ring.rotation.z = -t * 0.1;
      stars.rotation.y = t * 0.015;

      cubes.forEach((cube, i) => {
        const d = cube.userData;
        const a = d.angle + t * d.speed;
        cube.position.x = Math.cos(a) * d.radius;
        cube.position.z = Math.sin(a) * d.radius * 0.65;
        cube.position.y = d.yOffset + Math.sin(t * 0.9 + i) * 0.65;
        cube.rotation.x = t * 0.4 + i;
        cube.rotation.y = t * 0.55 + i;
      });

      renderer.render(scene, camera);
    }
    animate();
  } catch {
    // Graceful silent fallback when offline or WebGL unavailable.
  }
}

/* ── 2. Animated Ghostty CLI Terminal Walkthroughs ──────────────────────── */
const SCENES = {
  bootstrap: {
    caption: 'Fresh Mac → hardened workstation in one command',
    copy: `git clone https://github.com/gofastercloud/groundhog.git ~/groundhog\ncd ~/groundhog\n./groundhog init-custom\nbash ansible/bootstrap.sh`,
    steps: [
      { type: 'cmd', prompt: '❯ ', text: 'git clone https://github.com/gofastercloud/groundhog.git ~/groundhog && cd ~/groundhog' },
      { type: 'out', cls: 't-muted', text: 'Cloning into \'groundhog\'... done.' },
      { type: 'cmd', prompt: '❯ ', text: './groundhog init-custom' },
      { type: 'out', cls: 't-ok', text: 'Initialised private overlay repo at: ~/groundhog/custom' },
      { type: 'cmd', prompt: '❯ ', text: 'bash ansible/bootstrap.sh' },
      { type: 'out', cls: 't-info', text: '==> Ensuring Xcode CLT, Homebrew, GNU Stow & Ansible... ✓' },
      { type: 'out', cls: 't-info', text: '==> Overlay detected: ~/groundhog/custom' },
      { type: 'out', cls: 't-teal', text: 'Authenticating sudo once for this Ansible run... ✓ (Touch ID)' },
      { type: 'out', cls: 't-ok', text: 'TASK [homebrew : Install core + custom Brewfiles + 24 VS Code extensions]  changed' },
      { type: 'out', cls: 't-ok', text: 'TASK [macos_defaults : Harden sshd (050-hardening.conf, ML-KEM-768 PQC)]   changed' },
      { type: 'out', cls: 't-ok', text: 'TASK [macos_defaults : Lock down OrbStack (expose_ports_to_lan=false)]     changed' },
      { type: 'out', cls: 't-ok', text: 'TASK [macos_defaults : Apply Shottr, BetterDisplay & duti handlers]        changed' },
      { type: 'out', cls: 't-ok', text: 'TASK [claude_code : Merge Seatbelt sandbox + secret deny rules]            changed' },
      { type: 'out', cls: 't-ok', text: 'TASK [Stow 12 packages + custom symlinks + TPM plugins + Gitleaks hook]    changed' },
      { type: 'out', cls: 't-peach', text: 'PLAY RECAP  localhost: ok=118  changed=42  failed=0  (sudo ticket revoked)' },
    ],
  },
  agentic: {
    caption: 'Parallel agent worktrees (gwt + sesh) & offline container sandbox (agent-box)',
    copy: `gwt add feat/auth-refresh --sesh\nagent-box --image python:3.14-slim`,
    steps: [
      { type: 'cmd', prompt: '~/Code/app main ❯ ', text: 'gwt add feat/auth-refresh --sesh' },
      { type: 'out', cls: 't-info', text: 'Preparing worktree (new branch \'feat/auth-refresh\') → ../app-feat-auth-refresh' },
      { type: 'out', cls: 't-teal', text: 'Copied .worktreeinclude entries → switching to tmux session app-feat-auth-refresh' },
      { type: 'cmd', prompt: '~/Code/app-feat-auth-refresh ❯ ', text: 'gwt' },
      { type: 'out', cls: 't-muted', text: '╭───┬───────────────────────────────┬───────────────────┬─────────╮' },
      { type: 'out', cls: 't-text',  text: '│ 0 │ ~/Code/app                    │ main              │ a1b2c3d │' },
      { type: 'out', cls: 't-ok',    text: '│ 1 │ ~/Code/app-feat-auth-refresh  │ feat/auth-refresh │ a1b2c3d │' },
      { type: 'out', cls: 't-muted', text: '╰───┴───────────────────────────────┴───────────────────┴─────────╯' },
      { type: 'cmd', prompt: '~/Code/app-feat-auth-refresh ❯ ', text: 'agent-box -- make verify' },
      { type: 'out', cls: 't-teal', text: 'agent-box: groundhog-agent-box:latest [network=none, --read-only, mount=$PWD:/workspace]' },
      { type: 'out', cls: 't-ok', text: '✓ --cap-drop=ALL  ✓ non-root agent  ✓ zero ~/.ssh / ~/.aws / host env' },
      { type: 'out', cls: 't-ok', text: 'All checks passed! 42 passed in 0.8s' },
    ],
  },
  agency: {
    caption: 'Zero-flag groundhog-agency onboarding + autonomous verified PRs across Claude, Antigravity & Codex',
    copy: `agency-install ~/Code/app --ship\nagency-dash up --vendor claude`,
    steps: [
      { type: 'cmd', prompt: '~/Code/app main ❯ ', text: 'agency-install ~/Code/app --ship' },
      { type: 'out', cls: 't-info', text: 'wrote: .agents/{orchestrator,roles,skills}, .claude/{agents,hooks,settings.json}, AGENTS.md, CODEOWNERS' },
      { type: 'out', cls: 't-teal', text: 'repo: gofastercloud/app (policy: autonomous)' },
      { type: 'out', cls: 't-ok', text: 'ok: agent-gh verified access to gofastercloud/app' },
      { type: 'out', cls: 't-ok', text: 'created labels: agent-authored, ready-for-agent, in-progress, needs-human, spec' },
      { type: 'out', cls: 't-ok', text: 'created ruleset main-autonomous (PR required, required_signatures, no force-push)' },
      { type: 'out', cls: 't-peach', text: 'merged harness PR: gofastercloud/app#21 (Signed & Verified by gofastercloud-agent[bot])' },
      { type: 'cmd', prompt: '~/Code/app main ❯ ', text: 'agency-dash up --vendor claude' },
      { type: 'out', cls: 't-ok', text: 'Ready! Run /spec <idea> → /next-all → offline agent-box TDD → reviewer → /retro (~/.agency-kb).' },
      { type: 'cmd', prompt: '~/Code/app main ❯ ', text: 'agency-kb search "ffmpeg audio" --top 3' },
      { type: 'out', cls: 't-teal', text: '[pitfall] ffmpeg sidechain ducking filter ordering (demo-builder)  (score 4.82)' },
    ],
  },
  adopt: {
    caption: 'Adopt Groundhog safely on an existing Mac — backup manifest, secret check & 1-command rollback',
    copy: `./groundhog adopt\n./groundhog adopt --apply\n./groundhog clean --restore`,
    steps: [
      { type: 'cmd', prompt: '~/groundhog main ❯ ', text: './groundhog adopt' },
      { type: 'out', cls: 't-info', text: 'Groundhog Adopt — Dry-Run Audit (no files modified)' },
      { type: 'out', cls: 't-text', text: '  Conflicting dotfiles to back up: 4 (~/.zshrc, ~/.gitconfig, ~/.ssh/config, ~/.tmux.conf)' },
      { type: 'out', cls: 't-teal', text: '  Extra Homebrew/VS Code entries → custom/Brewfile: 19' },
      { type: 'out', cls: 't-teal', text: '  Current Dock apps → custom/config.yml:            11' },
      { type: 'out', cls: 't-peach', text: '  WARNING: ~/.zshrc:42 looks like a secret/token assignment (will NOT be copied)' },
      { type: 'cmd', prompt: '~/groundhog main ❯ ', text: './groundhog adopt --apply' },
      { type: 'out', cls: 't-ok', text: 'Snapshot saved to: ~/.backups/groundhog-adopt-20261127-130500 (manifest.json)' },
      { type: 'out', cls: 't-ok', text: '  adopted: custom/Brewfile (+19), custom/config.yml (dock_apps: 11), custom/gitconfig, ~/.ssh/config.local' },
      { type: 'out', cls: 't-muted', text: 'Roll back any time: ./groundhog clean --restore' },
    ],
  },
  pqc: {
    caption: 'Hardware-bound Secure Enclave auth + NIST ML-KEM-768 PQC handshake',
    copy: `ssh -vT git@github.com o+e>| rg 'kex:|Server accepts key|Hi '`,
    steps: [
      { type: 'cmd', prompt: '~/groundhog main ❯ ', text: "ssh -vT git@github.com o+e>| rg 'kex:|Server accepts key|Hi '" },
      { type: 'out', cls: 't-teal', text: 'debug1: kex: algorithm: mlkem768x25519-sha256' },
      { type: 'out', cls: 't-info', text: 'debug1: kex: host key algorithm: ssh-ed25519' },
      { type: 'out', cls: 't-info', text: 'debug1: kex: server->client cipher: chacha20-poly1305@openssh.com MAC: <implicit>' },
      { type: 'out', cls: 't-info', text: 'debug1: kex: client->server cipher: chacha20-poly1305@openssh.com MAC: <implicit>' },
      { type: 'out', cls: 't-peach', text: 'debug1: Server accepts key: ~/.ssh/id_secretive.pub ECDSA explicit agent' },
      { type: 'out', cls: 't-ok', text: 'Hi gofastercloud! You\'ve successfully authenticated (private key never left Secure Enclave).' },
      { type: 'cmd', prompt: '~/groundhog main ❯ ', text: 'git log -1 --show-signature' },
      { type: 'out', cls: 't-ok', text: 'Good "git" signature with ECDSA key (Secretive Secure Enclave)' },
    ],
  },
  'install-app': {
    caption: 'Agent loads skills/groundhog/SKILL.md to install apps declaratively & safely',
    copy: `./groundhog check --tags "homebrew,dock"\n./groundhog ansible --tags "homebrew,dock"\nmake verify`,
    steps: [
      { type: 'cmd', prompt: 'agent ❯ ', text: 'read skills/groundhog/SKILL.md' },
      { type: 'out', cls: 't-mauve', text: 'Loaded skill: groundhog (public core vs custom/ overlay + verify gates)' },
      { type: 'out', cls: 't-info', text: 'Routing: brew "watchexec" → homebrew/.Brewfile (universal CLI)' },
      { type: 'out', cls: 't-info', text: 'Routing: cask "linear-linear" → custom/Brewfile + custom/config.yml (dock_apps)' },
      { type: 'cmd', prompt: '~/groundhog ❯ ', text: './groundhog check --tags "homebrew,dock"' },
      { type: 'out', cls: 't-teal', text: 'Dry-run (--check --diff): +1 core formula, +1 custom cask, +1 Dock item' },
      { type: 'cmd', prompt: '~/groundhog ❯ ', text: './groundhog ansible --tags "homebrew,dock"' },
      { type: 'out', cls: 't-ok', text: 'TASK [homebrew : Install core + custom Brewfiles]  changed (watchexec, linear-linear)' },
      { type: 'out', cls: 't-ok', text: 'TASK [dock : Configure Dock items]                 changed (+Linear.app)' },
      { type: 'cmd', prompt: '~/groundhog ❯ ', text: 'make verify' },
      { type: 'out', cls: 't-ok', text: '✓ gitleaks  ✓ ruff & ty  ✓ pytest (8 passed)  ✓ ansible-lint  ✓ verify-custom' },
      { type: 'out', cls: 't-peach', text: 'make verify: all checks passed (zero personal data leaked to public groundhog)' },
    ],
  },
};

let currentScene = 'bootstrap';
let speedMult = 1;
let playToken = 0;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function runScene(name) {
  currentScene = name;
  const myToken = ++playToken;
  const scene = SCENES[name];
  const out = document.getElementById('terminal-output');
  const caption = document.getElementById('term-caption');
  if (!out || !scene) return;

  out.innerHTML = '';
  if (caption) caption.textContent = scene.caption;

  for (const step of scene.steps) {
    if (playToken !== myToken) return;
    const line = document.createElement('div');
    line.className = 't-line';

    if (step.type === 'cmd') {
      const promptSpan = document.createElement('span');
      promptSpan.className = 't-prompt';
      promptSpan.textContent = step.prompt;
      const cmdSpan = document.createElement('span');
      cmdSpan.className = 't-cmd';
      const cursor = document.createElement('span');
      cursor.className = 't-cursor';
      line.append(promptSpan, cmdSpan, cursor);
      out.appendChild(line);

      if (prefersReducedMotion) {
        cmdSpan.textContent = step.text;
      } else {
        for (const ch of step.text) {
          if (playToken !== myToken) return;
          cmdSpan.textContent += ch;
          out.scrollTop = out.scrollHeight;
          await sleep(16 / speedMult);
        }
      }
      cursor.remove();
      await sleep((prefersReducedMotion ? 0 : 180) / speedMult);
    } else {
      line.classList.add(step.cls || 't-muted');
      line.textContent = step.text;
      out.appendChild(line);
      out.scrollTop = out.scrollHeight;
      await sleep((prefersReducedMotion ? 0 : 140) / speedMult);
    }
  }
}

document.querySelectorAll('.term-tab').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.term-tab').forEach((b) => {
      b.classList.remove('active');
      b.setAttribute('aria-selected', 'false');
    });
    btn.classList.add('active');
    btn.setAttribute('aria-selected', 'true');
    runScene(btn.dataset.scene);
  });
});

document.getElementById('replay-btn')?.addEventListener('click', () => runScene(currentScene));
document.getElementById('speed-btn')?.addEventListener('click', (e) => {
  speedMult = speedMult === 1 ? 2.5 : 1;
  e.target.textContent = speedMult === 1 ? '1x' : '2.5x';
});

document.getElementById('copy-scene-cmd')?.addEventListener('click', async (e) => {
  await copyText(SCENES[currentScene].copy, e.target);
});

document.getElementById('watch-agent-install')?.addEventListener('click', () => {
  const tab = document.querySelector('.term-tab[data-scene="install-app"]');
  if (tab) tab.click();
});

/* ── 3. Interactive Layer Explorer ──────────────────────────────────────── */
const LAYERS = {
  core: {
    title: '01 · Public Core (groundhog)',
    desc: 'Shared, hardware-agnostic defaults that work cleanly for any macOS developer on day one.',
    tree: `groundhog/
├── ansible/            # sudo, homebrew, macos_defaults, dock, dev_tools, opt-in roles
├── homebrew/.Brewfile  # Core CLIs, casks, fonts, 24 VS Code extensions (zero MAS bloat)
├── zsh/ nushell/       # Login zsh + primary Nushell (gwt, agent-box, cplast, yy)
├── ghostty/ tmux/ nvim/# Catppuccin Mocha terminal & editor stack
├── ssh/.ssh/config     # Secretive Secure Enclave + ML-KEM-768 PQC-first template
├── src/groundhog/      # Zero-dependency Python CLI & curses TUI (./groundhog)
├── custom.example/     # Starter template copied by ./groundhog init-custom
└── tests/              # pytest behavioural suite + config/Nushell checks (make verify)`,
    note: '✓ Safe to git pull upstream improvements forever — zero personal data touches this repo.',
  },
  custom: {
    title: '02 · Private Overlay (groundhog/custom/)',
    desc: 'Your own private Git repo (e.g. groundhog-private), git-ignored by Groundhog and wired automatically.',
    tree: `custom/                 # Separate private git repo (groundhog-private)
├── config.yml          # Flips on feature flags + overrides dock_apps
├── Brewfile            # Personal apps, AWS/AI CLIs, hardware security, MAS installs
├── gitconfig           # Your user.name & user.email → ~/.gitconfig.custom
├── links.conf          # Symlinks SSH hosts, authorized_keys, AWS, CLAUDE.md, GEMINI.md
├── copies.conf         # App-managed files seeded by link & saved by capture
└── tasks.yml           # Optional custom Ansible tasks (--tags custom)`,
    note: '✓ Run `./groundhog init-custom` once to scaffold and push your own private overlay.',
  },
  local: {
    title: '03 · Per-Machine Local Overrides (Untracked)',
    desc: 'Machine-specific tweaks that stay strictly on one Mac.',
    tree: `ansible/vars/config.yml          # Machine-only Ansible variable overrides
homebrew/.Brewfile.local         # Machine-only extra packages
~/.gitconfig.local               # Machine-only signing key or work email
~/.ssh/config.local              # Temporary or work-only SSH host entries
~/.zshrc.local                   # One-off shell tweaks`,
    note: '✓ Highest precedence; never committed to either public or private Git repos.',
  },
};

function renderLayer(key) {
  const data = LAYERS[key];
  const el = document.getElementById('layer-inspector');
  if (!el || !data) return;
  el.innerHTML = `
    <h3>${data.title}</h3>
    <p class="layer-desc">${data.desc}</p>
    <pre class="tree-block">${data.tree}</pre>
    <p class="layer-note">${data.note}</p>
  `;
}

document.querySelectorAll('.layer-card').forEach((card) => {
  card.addEventListener('click', () => {
    document.querySelectorAll('.layer-card').forEach((c) => c.classList.remove('active'));
    card.classList.add('active');
    renderLayer(card.dataset.layer);
  });
});

/* ── 4. Interactive custom/config.yml Builder ───────────────────────────── */
function updateYamlPreview() {
  const flags = {};
  document.querySelectorAll('.flag-toggle').forEach((input) => {
    flags[input.dataset.flag] = input.checked;
  });

  const lines = [
    '---',
    '# custom/config.yml — Private Groundhog overlay',
    '',
    `claude_code_enabled: ${flags.claude_code_enabled}`,
    `antigravity_enabled: ${flags.antigravity_enabled}`,
    `codex_enabled: ${flags.codex_enabled}`,
    `agent_git_enabled: ${flags.agent_git_enabled}`,
    `agency_enabled: ${flags.agency_enabled}`,
    `remote_login_enabled: ${flags.remote_login_enabled}`,
  ];
  if (flags.remote_login_enabled) {
    lines.push('mosh_enabled: true');
  }
  lines.push(
    `yubikey_enabled: ${flags.yubikey_enabled}`,
    `immurok_enabled: ${flags.immurok_enabled}`,
  );

  if (flags.agent_git_enabled) {
    lines.push(
      '',
      '# Per-repo merge policies (default: autonomous):',
      'agent_git_repo_policies:',
      '  your-org/sensitive-repo: human-review',
    );
  }

  if (flags.agency_enabled) {
    lines.push(
      '',
      'agency_repo_dir: "{{ home_dir }}/Code/projects/groundhog-agency"',
    );
  }

  if (flags.claude_code_enabled) {
    lines.push(
      '',
      '# Extra private directories blocked from Claude Code reads:',
      'claude_code_extra_deny:',
      '  - "Read(~/.work-secrets/**)"',
    );
  }

  lines.push(
    '',
    'dock_apps:',
    '  - /System/Applications/Mail.app',
    '  - /Applications/Google Chrome.app',
    '  - /Applications/Visual Studio Code.app',
    '  - /Applications/Ghostty.app',
  );

  const out = document.getElementById('yaml-output');
  if (out) out.textContent = lines.join('\n');
}

document.querySelectorAll('.flag-toggle').forEach((t) => {
  t.addEventListener('change', updateYamlPreview);
});

/* ── Copy Helpers ───────────────────────────────────────────────────────── */
async function copyText(text, btn) {
  try {
    await navigator.clipboard.writeText(text);
    const orig = btn.textContent;
    btn.textContent = 'Copied ✓';
    btn.classList.add('copied');
    setTimeout(() => {
      btn.textContent = orig;
      btn.classList.remove('copied');
    }, 1800);
  } catch {
    btn.textContent = 'Copy failed';
  }
}

document.querySelectorAll('[data-copy-target]').forEach((btn) => {
  btn.addEventListener('click', () => {
    const target = document.getElementById(btn.dataset.copyTarget);
    if (target) copyText(target.textContent.trim(), btn);
  });
});

document.getElementById('copy-yaml-btn')?.addEventListener('click', (e) => {
  const out = document.getElementById('yaml-output');
  if (out) copyText(out.textContent, e.target);
});

/* ── Boot ───────────────────────────────────────────────────────────────── */
initThreeScene();
renderLayer('core');
updateYamlPreview();
runScene('bootstrap');
