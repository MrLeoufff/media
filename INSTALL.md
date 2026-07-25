# Guide d’installation — MediaStack 2.2

Objectif : stack opérationnelle en **moins de 10 minutes**, sans éditer Compose ni Caddyfile.

---

## 1. Prérequis

Serveur Debian / Ubuntu / Raspberry Pi OS **64 bits**, accès root (`sudo`).

```bash
apt update && apt install -y git curl ca-certificates python3
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
docker compose version   # doit répondre
```

Ports utiles :

| Mode | Ports ouverts sur le serveur MediaStack |
|------|-----------------------------------------|
| Derrière un reverse-proxy (recommandé) | **80** (LAN) |
| Edge public (TLS Caddy) | **80** et **443** |

---

## 2. Installer MediaStack

```bash
git clone https://github.com/MrLeoufff/media.git /opt/mediastack
cd /opt/mediastack
git checkout v2.2.0

chmod +x bin/media bin/media-service
find lib modules tests -type f -name '*.sh' -exec chmod +x {} \;
ln -sf /opt/mediastack/bin/media /usr/local/bin/media

media version
```

Vous devez voir `MediaStack 2.2.0`.

---

## 3. Choisir le mode TLS

| Situation | Option | Effet |
|-----------|--------|--------|
| TLS géré **en amont** (Caddy/Nginx/Traefik sur un autre hôte) | `--tls off` | Backend HTTP (`http://domaine`) |
| MediaStack est **exposé directement** à Internet | `--tls auto` | HTTPS automatique via Caddy |

Exemple topologie recommandée :

```text
Internet → [edge HTTPS :80/443] → [MediaStack HTTP :80]
              m710q                     Aspire
```

---

## 4. Installer les services

### Cas A — Derrière un reverse-proxy (recommandé)

```bash
media module install jellyfin --domain media.example.fr --tls off
media module install homepage --domain media.example.fr --tls off
media module install portainer --domain media.example.fr --tls off
```

Sur l’edge (exemple Caddy) :

```caddy
media.example.fr {
    reverse_proxy 192.168.1.102:80
}
```

Remplacez l’IP par celle du serveur MediaStack.

### Cas B — Edge public (TLS Caddy)

```bash
media module install jellyfin --domain media.example.fr --tls auto
media module install homepage --domain media.example.fr --tls auto
media module install portainer --domain media.example.fr --tls auto
```

Le DNS du domaine doit pointer vers ce serveur. Les ports 80/443 doivent être joignables depuis Internet.

### Mode interactif

Sans options, MediaStack demande domaine + TLS :

```bash
media module install jellyfin
```

Caddy est installé automatiquement (dépendance de Jellyfin / Homepage).

---

## 5. Vérifier

```bash
media module list
media status
media doctor
```

Attendu :

* modules `caddy`, `jellyfin`, … en **activé**
* conteneurs up
* Doctor sans erreur bloquante

Accès :

* Jellyfin → `https://media.example.fr/` (via edge) ou l’URL affichée à l’install
* Homepage / Portainer selon modules installés

---

## 6. Après installation (ops)

```bash
media backup create          # première sauvegarde
media backup list
media status --json
media logs jellyfin --since 30m
```

Changer domaine / TLS plus tard :

```bash
media domain configure media.example.fr --tls off
```

---

## 7. Désinstaller un module

```bash
media module uninstall homepage --keep-data   # conserve /opt/media/...
media module uninstall homepage --purge --yes # supprime aussi les données
```

---

## Dépannage rapide

| Symptôme | Action |
|----------|--------|
| `media: command not found` | `ln -sf /opt/mediastack/bin/media /usr/local/bin/media` |
| Docker indisponible | `systemctl status docker` puis `systemctl start docker` |
| Conflit proxy `/` | Un seul module sur `/` (souvent Jellyfin). Les autres : path/sous-domaine dédié |
| Site inaccessible derrière edge | Vérifier `reverse_proxy IP:80` et `media domain status` (`tls=off`) |
| Certificat / HTTPS | En `tls off`, le TLS est **uniquement** sur l’edge — pas sur MediaStack |

Logs utiles :

```bash
media logs caddy --follow
media logs jellyfin --follow
docker ps
```

---

## Résumé minimal (copier-coller)

Derrière reverse-proxy :

```bash
apt update && apt install -y git curl ca-certificates python3
curl -fsSL https://get.docker.com | sh && systemctl enable --now docker

git clone https://github.com/MrLeoufff/media.git /opt/mediastack
cd /opt/mediastack && git checkout v2.2.0
chmod +x bin/media bin/media-service
find lib modules tests -type f -name '*.sh' -exec chmod +x {} \;
ln -sf /opt/mediastack/bin/media /usr/local/bin/media

media module install jellyfin  --domain media.example.fr --tls off
media module install homepage  --domain media.example.fr --tls off
media module install portainer --domain media.example.fr --tls off

media doctor
media backup create
```

Puis sur l’edge : `reverse_proxy <IP-MediaStack>:80`.
