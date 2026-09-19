# Docker Netlab - Sorbonne Université

## Présentation du projet
Ce projet, réalisé dans le cadre du Master 1 (Parcours RES) à Sorbonne Université, propose une solution légère et isolée pour l'expérimentation réseau. L'objectif est de remplacer les infrastructures matérielles lourdes (routeurs Cisco, switchs physiques) par un environnement conteneurisé performant basé sur **Docker**, **Open vSwitch (OVS)** et **FRRouting (FRR)**.

Le projet permet de simuler des topologies allant de la simple commutation de niveau 2 (L2) au routage inter-VLAN de niveau 3 (L3), tout en intégrant des fonctionnalités avancées d'ingénierie de trafic comme le **Port Mirroring (SPAN)**, le **Routage Dynamique (RIPv2)**, et l'émulation de contraintes réseau.

## Structure du dépôt
Le répertoire est organisé pour séparer les infrastructures réseaux (Topologies) des scénarios applicatifs (Labs) :

```text
.
├── Topologies/
│   ├── Topology1_InternetRequired/    # Topologie L2 (Switching) - Dépendances apt au runtime
│   ├── Topology2_InternetRequired/    # Topologie L3 (Routing Statique) - Dépendances apt au runtime
│   ├── Topology2_preconfigured/       # Topologie L3 préconfigurée pour usage hors-ligne
│   └── Topology3_preconfigured/       # Topologie L3 avancée (Routage Dynamique RIPv2)
│
├── Labs/
│   ├── ftp_scenario/                  # Test de transfert FTP sécurisé sur topologie L3
│   ├── Rlogin_scenario/               # Test de vulnérabilité Rlogin (TCP)
│   ├── ssh_scenario/                  # Test de connexion SSH/Telnet sur topologie L3
│   └── TFTP_scenario/                 # Test de transfert UDP et ports éphémères
│
├── captures_trafic/                   # Répertoire de stockage des captures .pcap (Topo 1, 2 et 3)
└── setup_solution.sh                  # Scripts d'orchestration et de câblage OVS/Veth
```

## Types de topologies
Le projet propose deux approches de déploiement :

1. **Topologies avec accès Internet :** Les dépendances logicielles (`iproute2`, `tcpdump`, etc.) sont téléchargées et installées dynamiquement lors de l'exécution du script via `apt update`.
2. **Topologies et labs préconfigurés :** Ces versions utilisent des images Docker construites localement en amont via des `Dockerfile`. Elles sont indispensables pour les environnements isolés (comme les postes en salles de TP sans accès internet externe) car elles embarquent nativement tous les outils réseau nécessaires.

## Utilisation des environnements préconfigurés (hors-ligne / salles de TP)

Cette section détaille la marche à suivre pour déployer les topologies et laboratoires préconfigurés (`Topology2_preconfigured`, `Topology3_preconfigured`, et tous les scénarios dans `Labs/`) dans un environnement sans accès à Internet.

Il existe deux approches pour obtenir les images Docker requises : la construction locale via les `Dockerfile` fournis (nécessite Internet une seule fois), ou le chargement direct depuis une archive `.tar`.

### Option A : construction locale des images (nécessite Internet)

Si vous disposez d'une connexion Internet temporaire, vous pouvez construire les images manuellement. Les noms d'images ci-dessous correspondent à ceux renseignés dans les fichiers `docker-compose.yaml` du projet.

**1. Pour les topologies de base (Client, Serveur, Sonde) :**
Depuis `Topologies/Topology2_preconfigured/Dockerfiles_List/` (ou Topology3) :
```bash
# Image Client
docker build -t client-img:latest -f client/Dockerfile .
# Image Serveur
docker build -t server-img:latest -f server/Dockerfile .
# Image Sonde
docker build -t sonde-img:latest -f sonde/Dockerfile .
```

**2. Pour la topologie 3 (image FRR avec RIPv2) :**
Depuis `Topologies/Topology3_preconfigured/Dockerfiles_List/router/` :
```bash
# Construction de l'image FRRouting personnalisée
docker build -t frr-rip-img:latest -f Dockerfile.frr .
```

**3. Pour les scénarios applicatifs (labs) :**
Depuis les répertoires respectifs (ex: `Labs/ftp_scenario/`, `Labs/TFTP_scenario/`, etc.) :
```bash
# Lab FTP
docker build -t ftp_scenario-server:latest -f Dockerfile.tme .
docker build -t ftp_scenario-client:latest -f Dockerfile.tme .

# Lab TFTP
docker build -t tftp-image:latest -f Dockerfile .

# Lab Rlogin
docker build -t rlogin-image:latest -f Dockerfile .
```

### Option B : flux de déploiement hors-ligne (save & load)

Pour les machines totalement isolées, utilisez la méthode d'archivage. Les images doivent être archivées dans un fichier unique qui sera placé à la racine du projet (`PRES/`).

**1. Exportation (sur une machine connectée) :**
Depuis le dossier racine `PRES/`, après avoir construit toutes les images, regroupez-les dans une archive unique :
```bash
docker save -o images_netlab.tar \
  client-img:latest server-img:latest sonde-img:latest \
  frrouting/frr:latest frr-rip-img:latest \
  ftp_scenario-server:latest ftp_scenario-client:latest \
  ssh_scenario-server:latest ssh_scenario-client:latest \
  tftp-image:latest rlogin-image:latest
```

> **IMPORTANT** (contexte d'exécution sur les machines de la PPTI) :
> La VM installée sur les machines PPTI possède déjà les archives `.tar` (qui ne sont pas présentes dans ce répo GitHub), il n'est donc pas nécessaire d'exécuter l'étape précédente (sauf à des fins de test additionnel).

**2. Chargement (sur la machine cible isolée) :**
Transférez le fichier `images_netlab.tar` à la racine de votre dossier `PRES/` et chargez-le :
```bash
docker load -i images_netlab.tar
```

Pour vérifier que toutes les images sont bien chargées :
```bash
docker images
```

### Exécution de l'environnement

Une fois les images chargées dans le cache local de Docker, vous pouvez lancer les scripts d'orchestration.

1. **Vérification du compose :** Les fichiers `docker-compose.yaml` préconfigurés sont déjà réglés pour utiliser ces images locales au lieu de tenter un `build`.
2. **Lancement :** Utilisez les scripts Bash fournis pour automatiser le câblage Open vSwitch et la configuration réseau.

Voici un exemple d'exécution :
```bash
chmod +x setup_solution3Lab.sh
./setup_solution3Lab.sh
```
# DOCKER-LAB
