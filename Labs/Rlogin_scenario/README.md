# Scénario Rlogin - Routage Inter-VLAN et Analyse de Vulnérabilité (Authentification par Confiance)

## Objectif du Lab
Ce scénario s'appuie sur la Topologie 2 (Open vSwitch + FRRouting) pour valider le routage Inter-VLAN et le mécanisme de Port Mirroring (SPAN) à l'aide d'un protocole d'administration à distance historique (TCP).

Le but principal est de démontrer les vulnérabilités critiques des anciens protocoles d'accès distant. Un client (VLAN 10) établit une session avec le serveur (VLAN 20) via le port TCP 513. L'infrastructure de monitoring (sonde) intercepte le trafic, permettant de vérifier deux failles majeures : l'absence totale de chiffrement (les commandes transitent en clair) et l'authentification aveugle basée sur la confiance réseau (fichier `.rhosts`), permettant une connexion sans mot de passe.

## Rôles des Conteneurs
L'infrastructure déploie 4 nœuds dont les configurations ont été spécifiquement adaptées pour ce test :
* **Client :** Équipé du paquet `rsh-client`, il initie la connexion d'administration distante vers le serveur.
* **Serveur :** Exécute le "super-serveur" `inetd` configuré pour écouter le port `rlogin`. Il intègre l'utilisateur `etudiant` dont le fichier de confiance `/home/etudiant/.rhosts` est volontairement mal configuré avec `+ +` (autorisant n'importe quelle adresse IP à se connecter).
* **Routeur :** Assure le routage des paquets TCP (FRRouting) entre le sous-réseau du client et celui du serveur.
* **Sonde :** Écoute silencieusement le port miroir configuré sur OVS et capture le trafic à l'aide de `tcpdump` configuré en mode écriture immédiate (`-U`).

## 1. Exécution du Déploiement Automatisé
Le script `setup_rlogin_lab.sh` provisionne l'infrastructure réseau (liens veth, OVS, routage FRR, SPAN). En fin d'exécution, il configure la faille `.rhosts` sur le serveur, lance la capture, et exécute une série de commandes automatisées (comme `ls -la` et `whoami`) depuis le client vers le serveur.

Pour lancer l'infrastructure et générer le trafic de test :
```bash
chmod +x setup_Rlogin.sh
sudo ./setup_Rlogin.sh
```

## 2. Visualisation du Trafic Capturé
Le test automatisé génère le fichier `capture_rlogin.pcap` contenant la preuve de l'échange vulnérable. Vous pouvez analyser cette capture de deux façons :

### Méthode A : En ligne de commande depuis la Sonde
Lisez le fichier `.pcap` directement depuis l'intérieur du conteneur d'analyse grâce à `tcpdump` :
```bash
docker exec -it sonde tcpdump -r /data/capture_rlogin.pcap -n
```

### Méthode B : Via Wireshark sur la machine hôte (VM Debian)
Le volume Docker configuré dans `docker-compose.yaml` exporte automatiquement la capture vers votre machine locale dans le dossier dédié :
1. Lancez **Wireshark** sur votre VM Debian.
2. Naviguez vers le répertoire partagé : `Fichier > Ouvrir > /home/debian/PRES/captures_trafic/trafic_topo2/capture_rlogin.pcap`.
3. Dans la barre de filtre Wireshark, tapez `tcp.port == 513` pour isoler la session.
4. **Observation clé :** Faites un clic droit sur un des paquets et sélectionnez **Follow > TCP Stream** (Suivre le flux TCP). Vous pourrez lire distinctement le nom de l'utilisateur, l'ouverture de la session système et les résultats des commandes tapées en texte clair, confirmant l'absence de sécurité.

## 3. Expérimentation Manuelle en Temps Réel
Pour observer le comportement du réseau et du protocole en direct, vous pouvez reproduire la connexion manuellement tout en écoutant l'interface cible. L'interface d'écoute sera le câble virtuel reliant le client à OVS côté hôte (`veth-clt-host`).

**Étape 1 : Lancement de l'écoute (Terminal 1)**
Sur la machine Debian, ouvrez Wireshark avec les droits super-utilisateur pour écouter le trafic :
```bash
sudo wireshark -i veth-clt-host -k
```
*(Appliquez le filtre `tcp.port == 513` dans Wireshark dès son ouverture pour isoler l'échange).*

**Étape 2 : Connexion et transfert interactif (Terminal 2)**
Ouvrez un second terminal sur la VM Debian et entrez dans le conteneur client :
```bash
docker exec -it client bash
```
Depuis le shell du client, initiez la connexion Rlogin avec l'utilisateur `etudiant` :
```bash
rlogin 10.1.20.2 -l etudiant
```

**Résultat attendu :** Dans Wireshark (Terminal 1), vous verrez l'acheminement des paquets TCP à travers le routeur en temps réel. Le *3-Way Handshake* TCP initialisera la session. Dans votre Terminal 2, vous obtiendrez un accès instantané au shell du serveur sans qu'aucun mot de passe ne vous soit demandé, validant l'exploitation du fichier `.rhosts`. Chaque commande que vous taperez sera ensuite visible en clair dans Wireshark.
