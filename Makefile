.PHONY: test syntax

test: syntax
	@git diff --check

syntax:
	@./tests/syntax.sh
