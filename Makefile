SHELL := bash

.PHONY: test lint dist

test:
	bash tests/static-render.sh
	bash tests/cli.sh
	bash tests/lifecycle.sh
	bash tests/docs.sh
	bash tests/supply-chain.sh

lint:
	bash -n install-matrix.sh tests/*.sh scripts/*.sh
	shellcheck --severity=warning -x -e SC1091 install-matrix.sh tests/*.sh scripts/*.sh

dist:
	bash scripts/build-release.sh dist
