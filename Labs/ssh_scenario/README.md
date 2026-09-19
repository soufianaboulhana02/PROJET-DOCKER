# Scénario SSH - Routage Inter-VLAN et Analyse de Trafic

## Objectif du Lab
Ce scénario de laboratoire s'appuie sur la Topologie 2 (Open vSwitch + FRRouting) pour valider le routage Inter-VLAN et le mécanisme de Port Mirroring (SPAN) à l'aide d'un flux de communication chiffré. 

Le but principal est de démontrer qu'un client (VLAN 10) peut établir une session SSH sécurisée avec un serveur (VLAN 20) au travers d'un routeur virtuel (FRR). Simultanément, le commutateur OVS duplique les trames réseau vers la sonde, permettant de vérifier que l'infrastructure de monitoring intercepte bien l'échange TCP et la négociation SSH, tout en confirmant l'impossibilité de lire le contenu chiffré en clair.

## Rôles des Conteneurs
L'infrastructure déploie 4 nœuds dont les configurations ont été spécifiquement adaptées pour ce test :
* **Client :** Équipé des paquets `openssh-client` et `sshpass`, il initie les requêtes de connexion vers le serveur de manière automatisée ou interactive.
* **Serveur :** Exécute le démon `openssh-server` (`service ssh start`) et possède un utilisateur préconfiguré `etudiant` (mot de passe : `reseau`) prêt à recevoir des connexions.
* **Routeur :** Assure le routage des paquets IP entre le sous-réseau du client et celui du serveur.
* **Sonde :** Écoute silencieusement le port miroir configuré sur OVS et capture le trafic à l'aide de `tcpdump`.

## 1. Exécution du Déploiement Automatisé
Le script `setup_sshLab.sh` s'occupe de provisionner toute l'infrastructure réseau (liens veth, OVS, routage FRR, SPAN). En fin d'exécution, il réalise le test automatiquement : il démarre le service SSH sur le serveur, lance la capture sur la sonde, et exécute une commande SSH non-interactive depuis le client via `sshpass`.

Pour lancer l'infrastructure et générer le premier trafic de test :
```bash
chmod +x setup_sshLab.sh
./setup_sshLab.sh
```

## 2. Visualisation du Trafic Capturé
Le test automatisé génère le fichier `capture_ssh.pcap` contenant la preuve de l'échange. Vous pouvez analyser cette capture de deux façons :

### Méthode A : En ligne de commande depuis la Sonde
Lisez le fichier `.pcap` directement depuis l'intérieur du conteneur d'analyse grâce à `tcpdump` :
```bash
docker exec -it sonde tcpdump -r /data/capture_ssh.pcap -n
```

### Méthode B : Via Wireshark sur la machine hôte (VM Debian)
Le volume Docker configuré dans `docker-compose.yaml` exporte automatiquement la capture vers votre machine locale.
1. Lancez **Wireshark** sur votre VM Debian.
2. Naviguez vers le répertoire partagé : `Fichier > Ouvrir > /home/debian/PRES/captures_trafic/trafic_topo2/capture_ssh.pcap`.
3. Dans la barre de filtre Wireshark, appliquez le filtre `ssh` ou `tcp.port == 22` pour isoler spécifiquement la poignée de main TCP et la négociation du tunnel SSH.

## 3. Expérimentation Manuelle en Temps Réel
Pour aller plus loin, vous pouvez forger vous-même la connexion et observer le routage s'opérer en direct. L'interface d'écoute sera le câble virtuel reliant le serveur à OVS côté hôte (`veth-srv-host`).

**Étape 1 : Lancement de l'écoute (Terminal 1)**
Sur la machine Debian, ouvrez Wireshark avec les droits super-utilisateur pour écouter le trafic traversant l'OVS vers le serveur :
```bash
sudo wireshark -i veth-srv-host -k
```
*(Appliquez le filtre `ssh` dans Wireshark dès son ouverture).*

**Étape 2 : Connexion interactive (Terminal 2)**
Ouvrez un autre terminal sur la VM Debian et entrez dans le conteneur client :
```bash
docker exec -it client bash
```
Depuis le shell du client, initiez la connexion SSH vers le serveur (VLAN 20) avec l'utilisateur `etudiant` :
```bash
ssh etudiant@10.1.20.2
```
*Acceptez la clé hôte si demandé (`yes`), puis saisissez le mot de passe : `reseau`.*

**Résultat attendu :** Dans Wireshark (Terminal 1), vous verrez l'échange complet apparaître en direct : le routeur achemine la demande, le *3-Way Handshake* TCP s'effectue, suivi de l'échange des clés SSH (Protocol d'échange de clés, Cipher). Vous constaterez que votre session interactive dans le Terminal 2 génère des paquets chiffrés (`Encrypted response packet`) à chaque touche frappée, validant ainsi la sécurité du flux applicatif au-dessus de notre infrastructure SDN.
