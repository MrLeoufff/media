# MediaStack

MediaStack est une stack multimédia basée sur Docker, conçue pour centraliser l’installation, la gestion, la sécurisation et la sauvegarde de plusieurs services multimédias.

Services actuellement intégrés :

* Jellyfin
* Caddy
* Homepage
* Portainer

Le projet contient également des outils pour :

* gérer les services Docker ;
* configurer un nom de domaine ;
* sécuriser le serveur ;
* gérer le pare-feu ;
* configurer SSH ;
* installer Fail2ban ;
* vérifier l’état du système ;
* créer et restaurer des sauvegardes.

---

## Structure du projet

```text
mediastack/
├── bin/
│   ├── media
│   └── media-service
├── compose/
│   ├── caddy.yml
│   ├── homepage.yml
│   ├── jellyfin.yml
│   └── portainer.yml
├── conf/
│   └── Caddyfile
├── lib/
│   ├── backup/
│   │   ├── backup.sh
│   │   ├── create.sh
│   │   └── restore.sh
│   ├── core/
│   │   ├── common.sh
│   │   ├── constants.sh
│   │   ├── output.sh
│   │   └── router.sh
│   ├── docker/
│   │   ├── dashboard.sh
│   │   └── services.sh
│   ├── security/
│   │   ├── audit.sh
│   │   ├── fail2ban.sh
│   │   ├── firewall.sh
│   │   ├── security.sh
│   │   ├── ssh.sh
│   │   └── updates.sh
│   ├── services/
│   │   └── manager.sh
│   ├── system/
│   │   └── doctor.sh
│   └── web/
│       ├── domain.sh
│       └── homepage.sh
├── media.sh
├── .gitignore
└── README.md
```

---

## Prérequis

Système recommandé :

* Debian
* Ubuntu Server
* Raspberry Pi OS 64 bits

Architecture compatible :

* amd64
* arm64

Dépendances principales :

* Git
* Curl
* Docker
* Docker Compose Plugin

---

## Installation des dépendances

Mettre à jour le système :

```bash
apt update
apt upgrade -y
```

Installer les paquets nécessaires :

```bash
apt install -y git curl ca-certificates
```

Installer Docker :

```bash
curl -fsSL https://get.docker.com | sh
```

Activer et démarrer Docker :

```bash
systemctl enable --now docker
```

Vérifier l’installation :

```bash
docker --version
docker compose version
```

---

## Installation de MediaStack

Cloner le dépôt :

```bash
git clone https://github.com/MrLeoufff/media.git /opt/mediastack
```

Entrer dans le dossier :

```bash
cd /opt/mediastack
```

Vérifier les permissions des scripts :

```bash
chmod +x media.sh
chmod +x bin/media
chmod +x bin/media-service
find lib -type f -name "*.sh" -exec chmod +x {} \;
```

Lancer MediaStack :

```bash
./media.sh
```

---

## Commande globale

Le script principal est :

```bash
/opt/mediastack/media.sh
```

Il est également possible d’utiliser les exécutables présents dans :

```text
/opt/mediastack/bin/
```

Exemples :

```bash
/opt/mediastack/bin/media
/opt/mediastack/bin/media-service
```

Pour pouvoir utiliser la commande depuis n’importe quel emplacement, créer un lien symbolique :

```bash
ln -sf /opt/mediastack/bin/media /usr/local/bin/media
```

Puis lancer :

```bash
media
```

---

## Services Docker

Les fichiers Docker Compose se trouvent dans le dossier :

```text
/opt/mediastack/compose/
```

### Jellyfin

```text
compose/jellyfin.yml
```

Démarrage manuel :

```bash
docker compose -f compose/jellyfin.yml up -d
```

Arrêt :

```bash
docker compose -f compose/jellyfin.yml down
```

Logs :

```bash
docker compose -f compose/jellyfin.yml logs -f
```

### Caddy

```text
compose/caddy.yml
```

Démarrage :

```bash
docker compose -f compose/caddy.yml up -d
```

Logs :

```bash
docker compose -f compose/caddy.yml logs -f
```

Configuration :

```text
conf/Caddyfile
```

Après modification du Caddyfile :

```bash
docker compose -f compose/caddy.yml restart
```

### Homepage

```text
compose/homepage.yml
```

Démarrage :

```bash
docker compose -f compose/homepage.yml up -d
```

### Portainer

```text
compose/portainer.yml
```

Démarrage :

```bash
docker compose -f compose/portainer.yml up -d
```

---

## Vérification des services

Afficher les conteneurs actifs :

```bash
docker ps
```

Afficher tous les conteneurs :

```bash
docker ps -a
```

Afficher les projets Docker Compose :

```bash
docker compose ls
```

Afficher l’utilisation des ressources :

```bash
docker stats
```

Afficher l’espace utilisé par Docker :

```bash
docker system df
```

---

## Gestion d’un service

Pour redémarrer un service :

```bash
docker restart NOM_DU_CONTENEUR
```

Pour arrêter un service :

```bash
docker stop NOM_DU_CONTENEUR
```

Pour démarrer un service :

```bash
docker start NOM_DU_CONTENEUR
```

Pour consulter ses logs :

```bash
docker logs -f NOM_DU_CONTENEUR
```

---

## Configuration du domaine

La configuration du reverse proxy est stockée dans :

```text
conf/Caddyfile
```

Après modification :

```bash
docker compose -f compose/caddy.yml restart
```

Vérifier les logs Caddy :

```bash
docker compose -f compose/caddy.yml logs --tail=100
```

Le nom de domaine doit pointer vers l’adresse IP publique du serveur.

Les ports suivants doivent être accessibles :

```text
80/tcp
443/tcp
```

---

## Pare-feu

Vérifier l’état du pare-feu :

```bash
ufw status verbose
```

Autoriser SSH :

```bash
ufw allow OpenSSH
```

Autoriser HTTP et HTTPS :

```bash
ufw allow 80/tcp
ufw allow 443/tcp
```

Activer le pare-feu :

```bash
ufw enable
```

Attention à toujours autoriser SSH avant d’activer UFW sur un serveur distant.

---

## Sauvegardes

Les scripts de sauvegarde sont situés dans :

```text
lib/backup/
```

Le dossier de stockage local des sauvegardes est :

```text
/opt/mediastack/backup/
```

Ce dossier est volontairement exclu du dépôt Git.

Créer une sauvegarde :

```bash
bash lib/backup/create.sh
```

Ou selon les commandes intégrées :

```bash
./media.sh
```

Les archives peuvent contenir :

* les fichiers de configuration ;
* les fichiers Compose ;
* les scripts MediaStack ;
* certaines configurations applicatives ;
* les données persistantes selon la configuration du script.

Lister les sauvegardes :

```bash
ls -lh /opt/mediastack/backup/
```

---

## Restauration

Les scripts de restauration se trouvent dans :

```text
lib/backup/restore.sh
```

Avant une restauration, arrêter les services concernés :

```bash
docker ps
```

Puis utiliser le script de restauration :

```bash
bash lib/backup/restore.sh
```

Toujours conserver une copie supplémentaire de la sauvegarde avant de lancer une restauration.

---

## Mise à jour de MediaStack

Entrer dans le projet :

```bash
cd /opt/mediastack
```

Récupérer les dernières modifications :

```bash
git pull
```

Vérifier l’état :

```bash
git status
```

Mettre à jour les images Docker :

```bash
docker compose -f compose/jellyfin.yml pull
docker compose -f compose/caddy.yml pull
docker compose -f compose/homepage.yml pull
docker compose -f compose/portainer.yml pull
```

Recréer les conteneurs :

```bash
docker compose -f compose/jellyfin.yml up -d
docker compose -f compose/caddy.yml up -d
docker compose -f compose/homepage.yml up -d
docker compose -f compose/portainer.yml up -d
```

---

## Mise à jour du dépôt Git

Afficher les modifications :

```bash
git status
```

Ajouter les fichiers :

```bash
git add .
```

Créer un commit :

```bash
git commit -m "Description des modifications"
```

Envoyer vers GitHub :

```bash
git push
```

---

## Fichiers exclus de Git

Le fichier `.gitignore` exclut notamment :

```text
backup/
*.backup*
```

Les éléments suivants ne doivent jamais être ajoutés au dépôt :

* clés SSH privées ;
* mots de passe ;
* tokens d’accès ;
* fichiers `.env` contenant des secrets ;
* archives de sauvegarde ;
* certificats privés ;
* bases de données ;
* données personnelles.

Vérifier qu’aucun secret n’est suivi :

```bash
git ls-files | grep -E '(^|/)\.env$|password|credentials|secret|private|id_ed25519'
```

---

## Migration vers une autre machine

Pour installer la même stack sur une autre machine, par exemple un PC Aspire :

### Sur la machine source

Créer une sauvegarde :

```bash
cd /opt/mediastack
bash lib/backup/create.sh
```

Lister les conteneurs et leurs volumes :

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Mounts}}'
docker volume ls
```

Copier séparément les données persistantes qui ne sont pas présentes dans Git.

### Sur la machine cible

Installer Docker et Git :

```bash
apt update
apt install -y git curl ca-certificates
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
```

Cloner MediaStack :

```bash
git clone https://github.com/MrLeoufff/media.git /opt/mediastack
cd /opt/mediastack
```

Restaurer les données persistantes.

Démarrer les services :

```bash
docker compose -f compose/jellyfin.yml up -d
docker compose -f compose/caddy.yml up -d
docker compose -f compose/homepage.yml up -d
docker compose -f compose/portainer.yml up -d
```

Vérifier :

```bash
docker ps
docker compose ls
```

---

## Diagnostic

Vérifier les conteneurs en erreur :

```bash
docker ps -a
```

Consulter les derniers logs :

```bash
docker logs --tail=100 NOM_DU_CONTENEUR
```

Vérifier l’espace disque :

```bash
df -h
```

Vérifier la mémoire :

```bash
free -h
```

Vérifier les ports ouverts :

```bash
ss -lntup
```

Vérifier l’état de Docker :

```bash
systemctl status docker
```

Redémarrer Docker :

```bash
systemctl restart docker
```

Le projet contient également un script de diagnostic :

```text
lib/system/doctor.sh
```

Il peut être lancé avec :

```bash
bash lib/system/doctor.sh
```

---

## Sécurité

Les scripts de sécurité se trouvent dans :

```text
lib/security/
```

Ils permettent notamment de gérer :

* les mises à jour système ;
* SSH ;
* UFW ;
* Fail2ban ;
* les audits de sécurité.

Toujours vérifier les règles SSH et UFW avant de les appliquer sur une machine distante.

---

## Dépôt

Dépôt GitHub :

```text
https://github.com/MrLeoufff/media
```

Branche principale :

```text
main
```

---

## Auteur

René Leliard
MrLeoufff
