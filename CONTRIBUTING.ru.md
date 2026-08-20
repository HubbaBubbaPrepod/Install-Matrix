# Участие в разработке

> [English version](CONTRIBUTING.md)

Спасибо за улучшение Install-Matrix. Изменения root-установщика должны легко проверяться, откатываться и тестироваться.

## Подготовка окружения

Нужны Bash, Python 3 с PyYAML, ShellCheck, yamllint и Node.js для markdownlint.

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

## Pull request

- опишите проблему пользователя и риски;
- добавьте тесты для каждого изменения поведения;
- обновите README, документацию и `CHANGELOG.md`;
- сохраняйте совместимость интерактивного режима, если изменение не объявлено breaking;
- не добавляйте pipe-to-shell, изменяемую привилегированную загрузку или настоящий секрет;
- по возможности используйте заголовки в стиле Conventional Commits.

Настоящую установку проверяйте только на одноразовой поддерживаемой VM, никогда — на production homeserver.

Отправляя вклад, вы соглашаетесь лицензировать его по лицензии MIT этого репозитория.
