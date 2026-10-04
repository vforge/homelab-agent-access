.PHONY: test syntax cli lint integration

test: syntax cli
	@git diff --check

syntax:
	@./tests/syntax.sh

cli:
	@./tests/cli.sh

lint:
	@shellcheck -x bin/admin-transport bin/create bin/list bin/remove \
		remote/homelab-agent-dispatch remote/homelab-agent-dispatch-root \
		tests/cli.sh tests/integration.sh tests/syntax.sh

integration:
	@./tests/integration.sh
