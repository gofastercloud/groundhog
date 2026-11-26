# Verification for the dotfiles repo. Run `make verify` before committing.
# Optional tools (pre-commit, ansible, ansible-lint) are skipped when missing.

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
NU_DIR := nushell/Library/Application Support/nushell

.PHONY: verify precommit test nu ansible-syntax ansible-lint

verify: precommit test nu ansible-syntax ansible-lint
	@echo "make verify: all checks passed"

precommit:
	@if command -v pre-commit >/dev/null; then \
		pre-commit run --all-files; \
	else \
		echo "SKIP: pre-commit not installed"; \
	fi

test:
	tests/test_setup.sh

nu:
	@if command -v nu >/dev/null; then \
		tests/nu_startup_check.sh "$(NU_DIR)" && echo "nu startup check passed"; \
	else \
		echo "SKIP: nu not installed"; \
	fi

ansible-syntax:
	@if command -v ansible-playbook >/dev/null; then \
		cd ansible && ansible-playbook -i localhost, setup.yml --syntax-check; \
	else \
		echo "SKIP: ansible-playbook not installed"; \
	fi

ansible-lint:
	@if command -v ansible-lint >/dev/null; then \
		ANSIBLE_DEPRECATION_WARNINGS=0 ansible-lint --offline ansible; \
	else \
		echo "SKIP: ansible-lint not installed"; \
	fi
