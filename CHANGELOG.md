# Changelog MediaStack

## [2.1.0] — 2026-07-25

### Ajouté
- Architecture modulaire (`modules/`, `enabled/`, `module.yml`)
- `media module install|uninstall` zero-touch
- Génération automatique du Caddyfile (`tls off|auto`)
- Doctor enrichi (modules, Fail2ban, SSH, connectivité)
- Tests smoke et lifecycle mock
- Sauvegardes avec manifeste et checksum SHA-256 (`media backup prune`)
- `media status` synthétique (+ `--json`)
- `media logs` avec `--follow` / `--since`
- Versioning (`VERSION`, commit Git, channel)
- CI GitHub Actions (bash -n, ShellCheck, tests)

### Modifié
- Topologie reverse-proxy documentée (edge amont / backend HTTP)
- Absence de backup considérée comme normale par le Doctor
