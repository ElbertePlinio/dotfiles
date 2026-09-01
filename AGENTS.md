This is Elberte's personal dotfiles source repository, managed with chezmoi.
Shared agent policy lives in `.chezmoitemplates/agents-shared*.md`.
Harness adapters compose that policy rather than duplicating it.
`agent-config-sync` owns agent configuration validation and scoped apply.

`dev-freshness` reports first-party tools on this machine that have fallen
behind their repository or release channel, and a systemd user timer runs it
daily. It discovers its own targets, so a new app needs no registration: it is
picked up once the machine holds an installed AppImage beside the repo's
`scripts/install.sh`, a globally installed `@pickforge/*` package, a cargo
binary built from the checkout, or a launcher in `~/.local/bin` that runs a
script inside the checkout. A checkout on its own is deliberately not a target.
Override with `~/.config/dev-freshness/extra` and `~/.config/dev-freshness/ignore`.
