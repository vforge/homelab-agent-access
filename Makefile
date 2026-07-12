.PHONY: test syntax cli

test: syntax cli
	@git diff --check

syntax:
	@./tests/syntax.sh

cli:
	@./tests/cli.sh
