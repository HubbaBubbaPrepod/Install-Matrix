# Contributing

> [Русская версия](CONTRIBUTING.ru.md)

Thank you for improving Install-Matrix. Changes to a root installer must be reviewable, reversible and tested.

## Development setup

Required tools: Bash, Python 3 with PyYAML, ShellCheck, yamllint and Node.js for markdownlint.

```bash
bash -n install-matrix.sh tests/*.sh scripts/*.sh
shellcheck --severity=warning -x -e SC1091 install-matrix.sh tests/*.sh scripts/*.sh
bash tests/static-render.sh
bash tests/cli.sh
bash tests/lifecycle.sh
bash tests/docs.sh
bash tests/supply-chain.sh
yamllint .github .yamllint.yml
npx --yes markdownlint-cli2@0.18.1 "**/*.{md,MD}" "#data"
```

## Pull requests

- explain the user problem and risk;
- update tests for every behavioural change;
- update README/docs and `CHANGELOG.md`;
- preserve interactive compatibility unless the change is explicitly breaking;
- never add a pipe-to-shell command, mutable privileged download or real credential;
- use Conventional Commit-style subjects when practical.

Real installation changes should be exercised on a disposable supported VM. Never run E2E tests against a production homeserver.

By contributing, you agree that your contribution is licensed under the repository's MIT license.
