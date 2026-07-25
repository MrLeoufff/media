# MediaStack 2.2

MediaStack automatise l’installation, la configuration et l’exploitation d’une stack multimédia Docker.

**Principe zero-touch** : aucune édition manuelle des fichiers Compose ni du Caddyfile. Une commande CLI provisionne dépendances, dossiers, réseau, reverse-proxy, conteneurs et diagnostic. La v2.2 ajoute la couche ops (backup, status, logs, versioning, CI).

Services intégrés :

* Jellyfin
* Caddy
* Homepage
* Portainer

---

## Installation rapide

Prérequis : Debian / Ubuntu Server / Raspberry Pi OS 64 bits, Docker + Compose plugin, Python 3.

```bash
apt update && apt install -y git curl ca-certificates python3
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker

git clone https://github.com/MrLeoufff/media.git /opt/mediastack
cd /opt/mediastack
git checkout v2.2.0
chmod +x bin/media bin/media-service
find lib modules tests -type f -name '*.sh' -exec chmod +x {} \;
ln -sf /opt/mediastack/bin/media /usr/local/bin/media
```

> Release courante : tag Git `v2.2.0` (branche `main`).

Installer Jellyfin (et Caddy automatiquement) :

```bash
# Interactif : demande le domaine et le mode TLS
media module install jellyfin

# Ou explicite (scripts / non interactif)
media module install jellyfin --domain media.example.fr --tls off
media module install jellyfin --domain media.example.fr --tls auto
```

Pendant l’install (TTY), MediaStack propose :

1. **domaine** (ou Entrée = conserver / mode LAN)  
2. **mode TLS** :
   - `off` — HTTP backend, TLS terminé en amont (ex. **m710q**)
   - `auto` — HTTPS automatique Caddy (MediaStack = edge public)

Sans TTY (CI/script), le mode mémorisé est conservé (`off` par défaut).

### Topologie reverse-proxy

| Rôle | Hôte | Rôle TLS |
|------|------|----------|
| Edge public (80/443) | ex. **m710q** | Termine HTTPS (`media.dwg-dev.fr` → backend LAN) |
| MediaStack | ex. **Aspire** | HTTP backend (`http://media…` ou `:80`) |

```bash
media domain configure media.dwg-dev.fr --tls off
media domain configure media.example.fr --tls auto
```

Vérifier :

```bash
media doctor
media module list
```

---

## Architecture

```text
mediastack/
├── bin/media                 # CLI principale (v2.2.0)
├── VERSION                   # version semver
├── CHANGELOG.md
├── modules/<nom>/
│   ├── module.yml            # manifeste (deps, storage, proxy)
│   ├── compose.yml           # artefact produit (ne pas éditer)
│   └── doctor.sh             # diagnostic module
├── enabled/                  # symlinks vers modules activés
├── conf/
│   ├── Caddyfile             # généré automatiquement
│   ├── domain                # domaine mémorisé
│   └── tls-mode              # off|auto
├── lib/                      # bibliothèques Bash (backup, status, …)
├── backup/                   # archives locales (ignoré par git)
├── tests/
│   ├── smoke_test.sh
│   └── lifecycle_mock_test.sh
├── .github/workflows/ci.yml
└── media.sh                  # legacy (deprecated)
```

Chemins runtime :

* Code : `/opt/mediastack`
* Données : `/opt/media`

---

## Commandes modules

```bash
media module list
media module info <module>
media module install <module> [--domain <fqdn>] [--tls off|auto]
media module uninstall <module> [--keep-data|--purge] [--yes]
media module enable <module>
media module disable <module>
media module doctor <module>
```

### Install (zero-touch)

```bash
media module install jellyfin \
  --domain media.dwg-dev.fr \
  --tls off
```

Enchaîne :

1. résolution des `dependencies`
2. création du réseau `mediastack_proxy`
3. création des dossiers `storage`
4. activation du module
5. régénération du Caddyfile
6. `docker compose up -d`
7. doctor du module
8. résumé

### Uninstall

```bash
media module uninstall homepage --keep-data   # défaut
media module uninstall homepage --purge --yes
```

Refuse la désinstallation si un autre module activé en dépend.

---

## Format `module.yml`

```yaml
apiVersion: mediastack/v1
name: jellyfin
displayName: Jellyfin
version: "1.0.0"
category: multimedia

container:
  name: jellyfin
  image: jellyfin/jellyfin:latest

network:
  name: mediastack_proxy

dependencies:
  - caddy

storage:
  - /opt/media/jellyfin/config
  - /opt/media/jellyfin/cache

proxy:
  enabled: true
  target: jellyfin:8096
  path: /

features:
  doctor: true
  install: true
  uninstall: true
```

Le bloc `proxy` alimente la génération automatique de `conf/Caddyfile`.

---

## Autres commandes

```bash
media start|stop|restart|update|dashboard
media status [--json]
media logs <module> [--follow] [--since 30m]
media service list|start|stop|restart|logs|update <service|all>
media domain configure <fqdn> [--tls off|auto]
media domain status
media security audit|fix|firewall|fail2ban|updates|ssh-audit
media backup create|list|verify|restore [--dry-run]|prune [--keep 5]
media doctor
media version
```

### Sauvegardes

Les archives sont créées sous `/opt/mediastack/backup/` :

* `mediastack-backup-YYYY-MM-DD_HHMMSS.tar.gz`
* checksum `.sha256`
* manifeste (version MediaStack, modules activés, domaine, TLS)

```bash
media backup create
media backup list
media backup verify
media backup restore --dry-run          # aucune modification FS
media backup restore                    # rsync --delete (destructif)
media backup prune --keep 5
```

`media backup restore --dry-run` vérifie l’archive et simule les `rsync` sans créer de dossiers ni écrire de données.

### Statut et logs

```bash
media status
media status --json
media logs jellyfin --follow
media logs caddy --since 30m
media version
```

---

## Doctor

```bash
media doctor
media module doctor jellyfin
```

Contrôles principaux :

* Docker / Compose et versions
* modules + enabled
* cohérence du proxy généré
* réseau `mediastack_proxy`
* health des services
* permissions storage
* sauvegardes
* UFW, Fail2ban (`ignoreip`), SSH

---

## Troubleshooting

### Fail2ban

```bash
media security fail2ban
fail2ban-client status sshd
```

La jail MediaStack définit un `ignoreip` LAN (127.0.0.1, RFC1918).  
Si Fail2ban ne démarre pas : `journalctl -u fail2ban -n 50`.

### SSH

```bash
media security ssh-audit
media security fix
```

Vérifie notamment `PasswordAuthentication` et `PermitRootLogin`.

### Proxy / domaine

```bash
media domain configure media.example.fr
media domain status
docker exec caddy caddy validate --config /etc/caddy/Caddyfile
```

Ne pas éditer `conf/Caddyfile` à la main : relancer `media domain configure` ou `media module install`.

---

## Tests

```bash
./tests/smoke_test.sh
./tests/lifecycle_mock_test.sh
```

---

## Roadmap

### Suite ops

* `media update` + rollback (sauvegarde de secours avant restore)
* `media diagnose <module>`
* pin des images modules + rollback
* config centralisée (`media config`)
* ShellCheck strict global

### Catalogue

* `catalog/` (Immich, Nextcloud, Vaultwarden, Paperless, FreshRSS, …)
* `media module search` / `validate`

### Plus loin

* API REST + Web UI
* monitoring / notifications
* Doctor matériel (Raspberry Pi)

---

## Legacy

`media.sh` (v1.6) est conservé pour compatibilité mais **deprecated**.  
Utiliser exclusivement `bin/media` (v2.2).
