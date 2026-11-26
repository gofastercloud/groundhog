# Verification and orchestration for Groundhog.
# Verification is local-first: missing tools FAIL by default so pre-push gates
# cannot silently report a false green. Pass ALLOW_SKIP=1 to opt out explicitly.

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
NU_DIR := nushell/Library/Application Support/nushell
ALLOW_SKIP ?= 0

.PHONY: tui apply check hooks doctor verify precommit python test nu ansible-syntax ansible-lint verify-custom vm-test

tui:
	./groundhog

apply:
	./groundhog ansible $(if $(TAGS),--tags "$(TAGS)",)

check:
	./groundhog check $(if $(TAGS),--tags "$(TAGS)",)

hooks:
	@command -v pre-commit >/dev/null || { echo "FAIL: pre-commit not installed (brew install pre-commit)" >&2; exit 1; }
	pre-commit install --hook-type pre-commit --hook-type pre-push --install-hooks
	@if [[ -d custom/.git && -f custom/.pre-commit-config.yaml ]]; then \
		(cd custom && pre-commit install --hook-type pre-commit --hook-type pre-push --install-hooks); \
	fi
	@echo "Installed pre-commit and pre-push hooks."

doctor:
	@missing=(); \
	for pair in \
		"gitleaks:gitleaks" \
		"shellcheck:shellcheck" \
		"ansible-playbook:ansible" \
		"ansible-lint:ansible-lint" \
		"yamllint:yamllint" \
		"nu:nushell" \
		"pre-commit:pre-commit" \
		"ruff:ruff" \
		"ty:ty" \
		"uv:uv" \
		"stow:stow"; do \
		bin="$${pair%%:*}"; pkg="$${pair#*:}"; \
		if command -v "$$bin" >/dev/null 2>&1; then \
			printf "  ✓ %-18s %s\n" "$$bin" "$$(command -v "$$bin")"; \
		else \
			printf "  ✗ %-18s MISSING (brew install %s)\n" "$$bin" "$$pkg"; \
			missing+=("$$pkg"); \
		fi; \
	done; \
	if (( $${#missing[@]} > 0 )); then \
		echo; \
		echo "Install missing tools with:"; \
		echo "  brew install $${missing[*]}"; \
		exit 1; \
	fi; \
	echo "All verification tools are installed."

verify: precommit python test nu ansible-syntax ansible-lint verify-custom
	@echo "make verify: all checks passed"

precommit:
	@if command -v pre-commit >/dev/null; then \
		pre-commit run --all-files; \
	elif [[ "$(ALLOW_SKIP)" == "1" ]]; then \
		echo "SKIP: pre-commit not installed (ALLOW_SKIP=1)"; \
	else \
		echo "FAIL: pre-commit not installed (run 'make doctor' or pass ALLOW_SKIP=1)" >&2; \
		exit 1; \
	fi

python:
	@if command -v ruff >/dev/null && command -v ty >/dev/null && command -v uv >/dev/null; then \
		ruff check src tests; \
		ruff format --check src tests; \
		ty check src tests; \
		uv run --frozen --group dev pytest -q; \
	elif [[ "$(ALLOW_SKIP)" == "1" ]]; then \
		echo "SKIP: ruff/ty/uv not installed (ALLOW_SKIP=1)"; \
	else \
		echo "FAIL: ruff, ty, and uv are required for Python checks (run 'make doctor')" >&2; \
		exit 1; \
	fi

test:
	tests/test_setup.sh

nu:
	@if command -v nu >/dev/null; then \
		tests/nu_startup_check.sh "$(NU_DIR)" && echo "nu startup check passed"; \
	elif [[ "$(ALLOW_SKIP)" == "1" ]]; then \
		echo "SKIP: nu not installed (ALLOW_SKIP=1)"; \
	else \
		echo "FAIL: nu not installed (run 'make doctor' or pass ALLOW_SKIP=1)" >&2; \
		exit 1; \
	fi

ansible-syntax:
	@if command -v ansible-playbook >/dev/null; then \
		cd ansible && ansible-playbook -i localhost, setup.yml --syntax-check; \
	elif [[ "$(ALLOW_SKIP)" == "1" ]]; then \
		echo "SKIP: ansible-playbook not installed (ALLOW_SKIP=1)"; \
	else \
		echo "FAIL: ansible-playbook not installed (run 'make doctor' or pass ALLOW_SKIP=1)" >&2; \
		exit 1; \
	fi

ansible-lint:
	@if command -v ansible-lint >/dev/null; then \
		ANSIBLE_DEPRECATION_WARNINGS=0 ansible-lint --offline ansible; \
	elif [[ "$(ALLOW_SKIP)" == "1" ]]; then \
		echo "SKIP: ansible-lint not installed (ALLOW_SKIP=1)"; \
	else \
		echo "FAIL: ansible-lint not installed (run 'make doctor' or pass ALLOW_SKIP=1)" >&2; \
		exit 1; \
	fi

verify-custom:
	./groundhog verify-custom

vm-test:
	scripts/vm_test.sh $(if $(VM_TAGS),--tags "$(VM_TAGS)",) $(if $(VM_IMAGE),--image "$(VM_IMAGE)",)
