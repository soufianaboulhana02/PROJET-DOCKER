# Topologie 2 (Préconfigurée) - Routage Inter-VLAN (OVS + FRR)

## Objectif du Lab
Ce scénario met en œuvre une infrastructure réseau segmentée (Niveau 3) reposant sur **Open vSwitch (OVS)** et un routeur **FRRouting (FRR)**. 

Le but principal est de valider le routage Inter-VLAN : le client (VLAN 10) et le serveur (VLAN 20) sont isolés dans des domaines de diffusion distincts. Pour communiquer, leur trafic applicatif doit transiter par le routeur virtuel. En parallèle, OVS est configuré avec une règle de duplication de port (SPAN/Port Mirroring) afin qu'une copie exacte de tous les échanges atteignant le serveur soit redirigée de manière transparente vers une sonde d'analyse.

## Rôles des Conteneurs
L'infrastructure déploie 4 nœuds distincts :
* **Client :** Génère les requêtes HTTP (VLAN 10).
* **Serveur :** Héberge un serveur web Python basique écoutant sur le port 80 (VLAN 20).
* **Routeur :** Équipement de niveau 3 (FRRouting) disposant d'une interface dans chaque VLAN pour acheminer les paquets IP.
* **Sonde :** Nœud d'observation réseau silencieux chargé de capturer le trafic dupliqué par le commutateur OVS.

## 1. Exécution du Déploiement Automatisé
Le script `setup_solution2Lab.sh` gère l'intégralité du cycle de vie : nettoyage, lancement des conteneurs, création des liens virtuels (`veth`), configuration des tags VLAN sur OVS, ajout des routes par défaut et configuration du miroir SPAN. 

À la fin de son exécution, le script effectue un test automatisé en lançant le serveur web, en capturant le trafic sur la sonde, et en effectuant un `curl` depuis le client.

Pour lancer l'infrastructure et le test, placez-vous dans le dossier et exécutez :
```bash
chmod +x setup_solution2Lab.sh
./setup_solution2Lab.sh
```

## 2. Visualisation du Trafic Capturé
Le test automatisé génère un fichier `.pcap` contenant la preuve que le routage et le port mirroring fonctionnent. Vous pouvez analyser ce trafic de deux manières :

### Méthode A : En ligne de commande depuis la Sonde
Vous pouvez lire le fichier de capture directement depuis l'intérieur du conteneur sonde en utilisant `tcpdump` :
```bash
docker exec -it sonde tcpdump -r /data/capture_topology2.pcap -n
```

### Méthode B : Via l'interface graphique Wireshark sur la VM Debian
Grâce au montage de volumes Docker configuré dans le `docker-compose.yaml`, le fichier de capture généré par la sonde est automatiquement sauvegardé sur votre machine hôte (VM Debian).

1. Ouvrez **Wireshark** sur votre machine Debian.
2. Allez dans **Fichier > Ouvrir** et naviguez vers le dossier de stockage : 
   `/home/debian/PRES/captures_trafic/trafic_topo2/`
3. Ouvrez le fichier `capture_topology2.pcap`.
4. Dans la barre de filtre Wireshark en haut, tapez `tcp` et appuyez sur Entrée pour isoler l'échange HTTP entre le client (10.1.10.2) et le serveur (10.1.20.2).

## 3. Expérimentation en Temps Réel
Vous pouvez également générer de nouveaux tests manuels et observer le réseau réagir en direct. Dans cet exercice, nous allons écouter l'interface de connexion du serveur au niveau de l'hôte Linux.

**Étape 1 : Lancement de l'écoute (Terminal 1)**
Sur votre machine Debian, lancez Wireshark avec les droits administrateur pour écouter directement sur le câble virtuel (côté hôte) reliant OVS au serveur :
```bash
sudo wireshark -i veth-srv-host -k
```
*(Une fois Wireshark ouvert, appliquez immédiatement le filtre `tcp` pour y voir plus clair).*

**Étape 2 : Génération du trafic (Terminal 2)**
Ouvrez un second terminal sur votre VM Debian et connectez-vous de manière interactive au conteneur client :
```bash
docker exec -it client bash
```
Une fois dans le shell du client, générez une requête HTTP vers l'adresse IP du serveur :
```bash
curl 10.1.20.2
```

**Résultat attendu :** Dans la fenêtre Wireshark du Terminal 1, vous verrez apparaître en temps réel le *3-Way Handshake* TCP (SYN, SYN-ACK, ACK) suivi de la requête HTTP GET et de la réponse du serveur Python, prouvant que la requête a traversé le routeur FRR et atteint sa destination avec succès.
