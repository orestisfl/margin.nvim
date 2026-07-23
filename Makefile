.PHONY: all fmt fmt-check lint typecheck test check deps

all: check

deps:
	@test -d deps/mini.nvim || git clone --depth 1 https://github.com/echasnovski/mini.nvim deps/mini.nvim

fmt:
	stylua lua plugin tests

fmt-check:
	stylua --check lua plugin tests

lint:
	selene lua plugin

typecheck:
	./scripts/typecheck.sh

test: deps
	./scripts/test.sh

# Everything a pre-commit run gates on.
check: fmt-check lint typecheck test
