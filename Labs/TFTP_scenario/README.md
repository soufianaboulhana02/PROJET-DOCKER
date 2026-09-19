# Scénario TFTP - Routage Inter-VLAN, Ports Éphémères et Analyse UDP

## Objectif du Lab
Ce scénario s'appuie sur la Topologie 2 (Open vSwitch + FRRouting) pour valider le routage Inter-VLAN et le mécanisme de Port Mirroring (SPAN) à l'aide d'un protocole de transfert de fichiers non orienté connexion (UDP).

Le but principal est de démontrer la complexité du filtrage et du routage UDP. Contrairement à TCP, le client TFTP (VLAN 10) initie la demande sur un port standard, mais le serveur (VLAN 20) répond sur un **port source aléatoire**. Le commutateur OVS duplique ces trames vers la sonde, permettant de vérifier que l'infrastructure réseau gère correctement le suivi de connexion (Connection Tracking) et intercepte la totalité de l'échange asymétrique.

## Rôles des Conteneurs
L'infrastructure déploie 4 nœuds dont les configurations ont été spécifiquement adaptées pour ce test :
* **Client :** Équipé du paquet `tftp-hpa`, il initie les requêtes de téléchargement (Read Request) vers le serveur de manière automatisée ou interactive.
* **Serveur :** Exécute le démon `in.tftpd` lié strictement à l'interface de son VLAN (`10.1.20.2:69`) et héberge un fichier texte de test dans `/srv/tftp/`.
* **Routeur :** Assure le routage des paquets IP (FRRouting) entre le sous-réseau du client et celui du serveur, permettant le retour des paquets UDP sur les ports éphémères.
* **Sonde :** Écoute silencieusement le port miroir configuré sur OVS et capture le trafic à l'aide de `tcpdump` configuré en mode écriture immédiate (`-U`).

## 1. Exécution du Déploiement Automatisé
Le script `setup_TFTPlab.sh` provisionne l'infrastructure réseau (liens veth, OVS, routage FRR, SPAN). En fin d'exécution, il réalise le test automatiquement : il démarre le service TFTP, crée le fichier cible, lance la capture sur la sonde, et exécute la récupération du fichier depuis le client.

Pour lancer l'infrastructure et générer le premier trafic de test :
```bash
chmod +x setup_tftp_lab.sh
sudo ./setup_tftp_lab.sh
```

## 2. Visualisation du Trafic Capturé
Le test automatisé génère le fichier `capture_tftp.pcap` contenant la preuve de l'échange. Vous pouvez analyser cette capture de deux façons :

### Méthode A : En ligne de commande depuis la Sonde
Lisez le fichier `.pcap` directement depuis l'intérieur du conteneur d'analyse grâce à `tcpdump` :
```bash
docker exec -it sonde tcpdump -r /data/capture_tftp.pcap -n
```

### Méthode B : Via Wireshark sur la machine hôte (VM Debian)
Le volume Docker configuré dans `docker-compose.yaml` exporte automatiquement la capture vers votre machine locale dans le dossier dédié :
1. Lancez **Wireshark** sur votre VM Debian.
2. Naviguez vers le répertoire partagé : `Fichier > Ouvrir > /home/debian/PRES/captures_trafic/trafic_topo2/capture_tftp.pcap`.
3. Dans la barre de filtre Wireshark, tapez `tftp` ou `tftp-data` pour isoler les commandes de contrôle et les données transférées.
4. **Observation clé :** Regardez les paquets de commande TFTP.

## 3. Expérimentation Manuelle en Temps Réel
Pour observer le comportement du réseau et du protocole en direct, vous pouvez reproduire le transfert manuellement tout en écoutant l'interface cible. L'interface d'écoute sera le câble virtuel reliant le client à OVS côté hôte (`veth-clt-host`).

**Étape 1 : Lancement de l'écoute (Terminal 1)**
Sur la machine Debian, ouvrez Wireshark avec les droits super-utilisateur pour écouter le trafic :
```bash
sudo wireshark -i veth-clt-host -k
```
*(Appliquez le filtre `udp` ou `tftp` dans Wireshark dès son ouverture pour isoler l'échange).*

**Étape 2 : Connexion et transfert interactif (Terminal 2)**
Ouvrez un second terminal sur la VM Debian et entrez dans le conteneur client :
```bash
docker exec -it client bash
```
Depuis le shell du client, initiez le téléchargement TFTP vers le serveur (VLAN 20) en mode verbeux (`-v`) pour voir le détail de l'exécution :
```bash
tftp -v 10.1.20.2 -c get test_tftp.txt
```
*(Contrairement au FTP, TFTP ne requiert aucune authentification. Le transfert s'exécute en une seule commande directe).*

**Résultat attendu :** Dans Wireshark (Terminal 1), vous verrez l'acheminement des paquets UDP à travers le routeur en temps réel. Contrairement au FTP, il n'y a pas de 3-Way Handshake d'initialisation. Vous verrez la requête de lecture (RRQ) partir vers le port 69, puis le serveur répondre instantanément depuis un port dynamique (éphémère) pour transférer les blocs de données du fichier `test.txt`. Cette manipulation valide que votre infrastructure (FRR) gère correctement le suivi de connexion UDP (Connection Tracking) pour autoriser le trafic de retour.
