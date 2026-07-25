# Changelog MediaStack

## [2.2.0] — 2026-07-25

### Ajouté
- Couche ops : sauvegardes avec manifeste + checksum SHA-256
- `media backup create|list|verify|restore [--dry-run]|prune`
- Restore fidèle via `rsync --delete` (échecs critiques bloquants)
- `media status` synthétique (+ `--json`)
- `media logs <module> [--follow|--since]`
- Versioning (`VERSION`, commit Git, channel) via `media version`
- Healthchecks Compose (Jellyfin, Homepage)
- CI GitHub Actions (`bash -n`, ShellCheck, smoke, lifecycle mock)

### Modifié
- `--dry-run` de restore réellement non modifiant (pas de `mkdir`)
- Smoke tests CI compatibles runner non-root (`media_die` isolé)
- `.gitignore` : ignore `/backup/` à la racine uniquement

## [2.1.0] — 2026-07-25

### Ajouté
- Architecture modulaire (`modules/`, `enabled/`, `module.yml`)
- `media module install|uninstall` zero-touch
- Génération automatique du Caddyfile (`tls off|auto`)
- Doctor enrichi (modules, Fail2ban, SSH, connectivité)
- Tests smoke et lifecycle mock

### Modifié
- Topologie reverse-proxy documentée (edge amont / backend HTTP)
- Absence de backup considérée comme normale par le Doctor
