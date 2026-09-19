# Scénario FTP - Routage Inter-VLAN et Analyse de Trafic en Clair

## Objectif du Lab
Ce scénario s'appuie sur la Topologie 2 (Open vSwitch + FRRouting) pour valider le routage Inter-VLAN et le mécanisme de Port Mirroring (SPAN) à l'aide d'un protocole de transfert de fichiers non chiffré (FTP).

L'objectif pédagogique principal, outre la validation du routage de niveau 3, est de démontrer les vulnérabilités des protocoles en clair. Contrairement au scénario SSH, la copie du trafic envoyée par OVS vers la sonde permettra de lire l'intégralité des échanges en clair dans Wireshark, y compris les identifiants de connexion (login/mot de passe) et le contenu du fichier transféré.

## Rôles des Conteneurs
L'infrastructure déploie 4 nœuds dont les configurations ont été spécifiquement adaptées pour ce test:
* **Client :** Équipé du paquet `ftp`, il est utilisé pour initier une connexion vers le serveur, s'authentifier et télécharger un fichier.
* **Serveur :** Exécute le démon FTP `vsftpd`. Un fichier de test (`test_tme.txt`) est généré à la volée dans le répertoire de l'utilisateur `etudiant` (mot de passe : `reseau`).
* **Routeur :** Assure le routage des paquets IP entre le VLAN 10 du Client (10.1.10.0/24) et le VLAN 20 du Serveur (10.1.20.0/24).
* **Sonde :** Écoute silencieusement le port miroir configuré sur OVS et capture le trafic à l'aide de `tcpdump`.

## 1. Exécution du Déploiement Automatisé
Le script `setup_ftpLab.sh` déploie l'infrastructure réseau (liens veth, OVS, routage FRR, miroir SPAN). En fin d'exécution, il lance un test automatisé : création du fichier de test, démarrage de `vsftpd`, lancement de la capture sur la sonde, et exécution d'un script FTP en mode passif depuis le client pour récupérer le fichier.

Pour lancer l'infrastructure et générer le premier transfert automatisé :
```bash
chmod +x setup_ftpLab.sh
./setup_ftpLab.sh
```

## 2. Visualisation du Trafic Capturé
Le test automatisé génère le fichier `capture_ftp2.pcap`. Vous pouvez analyser cette capture de deux façons :

### Méthode A : En ligne de commande depuis la Sonde
Lisez le fichier `.pcap` directement depuis l'intérieur du conteneur d'analyse :
```bash
docker exec -it sonde tcpdump -r /data/capture_ftp2.pcap -n
```

### Méthode B : Via Wireshark sur la machine hôte (VM Debian)
Le volume Docker configuré dans `docker-compose.yaml` exporte automatiquement la capture vers votre machine locale dans le dossier dédié:
1. Lancez **Wireshark** sur votre VM Debian.
2. Naviguez vers le répertoire partagé : `Fichier > Ouvrir > /home/debian/PRES/captures_trafic/trafic_topo2/capture_ftp2.pcap`.
3. Dans la barre de filtre Wireshark, tapez `ftp` ou `ftp-data` pour isoler les commandes de contrôle et les données transférées.
4. **Observation clé :** Regardez les paquets de commande FTP. Vous verrez distinctement `USER etudiant` et `PASS reseau` circuler en texte clair.

## 3. Expérimentation Manuelle en Temps Réel
Pour observer le comportement du réseau et du protocole en direct, vous pouvez reproduire le transfert manuellement tout en écoutant l'interface cible. L'interface d'écoute sera le câble virtuel reliant le serveur à OVS côté hôte (`veth-srv-host`).

**Étape 1 : Lancement de l'écoute (Terminal 1)**
Sur la machine Debian, ouvrez Wireshark avec les droits super-utilisateur pour écouter le trafic :
```bash
sudo wireshark -i veth-srv-host -k
```
*(Appliquez le filtre `ftp` dans Wireshark dès son ouverture pour isoler les commandes).*

**Étape 2 : Connexion et transfert interactif (Terminal 2)**
Ouvrez un second terminal sur la VM Debian et entrez dans le conteneur client :
```bash
docker exec -it client bash
```
Depuis le shell du client, initiez la connexion FTP vers le serveur (VLAN 20) :
```bash
ftp 10.1.20.2
```
*Identifiez-vous avec l'utilisateur `etudiant` et le mot de passe `reseau`. Une fois connecté, passez en mode passif et téléchargez le fichier :*
```bash
ftp> passive
ftp> get test_tme.txt
ftp> quit
```

**Résultat attendu :** Dans Wireshark (Terminal 1), vous verrez l'acheminement des paquets à travers le routeur en temps réel. Le *3-Way Handshake* TCP initialisera la session sur le port 21. Vous verrez ensuite vos frappes clavier (les commandes `USER` et `PASS`) interceptées par le miroir SPAN en clair, ainsi que l'ouverture d'un port dynamique (mode passif) pour le transfert effectif du fichier `test_tme.txt`.
