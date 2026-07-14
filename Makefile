.PHONY: test syntax cli integration

test: syntax cli
	@git diff --check

syntax:
	@./tests/syntax.sh

cli:
	@./tests/cli.sh

integration:
	@./tests/integration.sh
