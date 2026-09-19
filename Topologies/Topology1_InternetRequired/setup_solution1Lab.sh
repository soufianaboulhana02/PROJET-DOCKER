#!/bin/bash

# Arrêt du script en cas d'erreur
set -e

echo "=== 0. Nettoyage de l'environnement (Clean State) ==="
echo " -> Nettoyage des conteneurs..."
docker rm -f server client sonde 2>/dev/null || true

echo " -> Nettoyage du réseau Docker..."
docker network rm net-ares 2>/dev/null || true

echo " -> Nettoyage d'Open vSwitch (OVS)..."
sudo ovs-vsctl del-br br-ares 2>/dev/null || true

echo " -> Nettoyage des interfaces virtuelles orphelines..."
sudo ip link delete veth-srv-host 2>/dev/null || true
sudo ip link delete veth-clt-host 2>/dev/null || true
sudo ip link delete veth-snd-host 2>/dev/null || true


echo "=== 1. Préparation de l'hôte et vérification d'Open vSwitch ==="

# Vérification silencieuse de l'installation du paquet
if ! dpkg -s openvswitch-switch >/dev/null 2>&1; then
    echo " -> Le paquet openvswitch-switch n'est pas installé. Installation en cours..."
    sudo apt update -qq && sudo apt install -y openvswitch-switch
else
    echo " -> Le paquet openvswitch-switch est déjà installé. Maintien de la configuration."
fi


# Redirection d'erreurs avec 2>/dev/null || true
sudo ovs-vsctl add-br br-ares 2>/dev/null || true
sudo ip link set br-ares up  # activer l'OVS

echo "=== 2. Lancement de l'infrastructure Docker ==="
docker compose up -d # lancement conteneurs en detach mode

echo "=== 3. Installation des dépendances dans les conteneurs ==="
# L'option -qq pour réduire au maximum affichage des messages
docker exec server apt update -qq && docker exec server apt install -y -qq procps iproute2 python3
docker exec client apt update -qq && docker exec client apt install -y -qq iputils-ping curl 
docker exec sonde apt update -qq && docker exec sonde apt install -y -qq tcpdump

echo "=== 4. Câblage réseau OVS (Veth Pairs & Namespaces) ==="

# Fonction générique pour connecter un conteneur à OVS
connect_to_ovs() {
	local CONTAINER=$1
	local IP_ADDR=$2
	local PREFIX=$3

	local V_HOST="veth-${PREFIX}-host"
	local V_CONT="veth-${PREFIX}-cont"

	echo "Connexion de $CONTAINER ($IP_ADDR) via $V_HOST / $V_CONT..."

	# Nettoyage d'anciennes interfaces si elles existent
	sudo ip link delete $V_HOST 2>/dev/null || true

	# Créer la paire veth
	sudo ip link add $V_HOST type veth peer name $V_CONT
	# Attacher veth host à OVS
	sudo ovs-vsctl add-port br-ares $V_HOST 

	# Récupérer PID du conteneur
	local PID=$(docker inspect -f '{{.State.Pid}}' $CONTAINER)
	# Attacher le namespace réseau du conteneur au veth  conteneur
	sudo ip link set $V_CONT netns $PID

	# Mettre veth conteneur en up et lui affecter une IP
	sudo nsenter -t $PID -n ip link set $V_CONT up
	sudo nsenter -t $PID -n ip addr add $IP_ADDR/24 dev $V_CONT

	# Mettre veth host en up 
	sudo ip link set $V_HOST up 
}

connect_to_ovs "server" "10.0.0.2" "srv"
connect_to_ovs "client" "10.0.0.3" "clt"
connect_to_ovs "sonde" "10.0.0.4" "snd"

echo "=== 5. Configuration du Port Mirroring (SPAN) sur OVS ==="
# Récupération dynamique des UUIDs
UUID_SRV=$(sudo ovs-vsctl get port veth-srv-host _uuid)
UUID_SND=$(sudo ovs-vsctl get port veth-snd-host _uuid)


# Suppression d'un ancien miroir éventuel, puis création du nouveau
sudo ovs-vsctl -- --id=@m get Mirror mon-miroir 2>/dev/null && sudo ovs-vsctl -- clear Bridge br-ares mirrors || true

#TOUT ceci représente une seule commande de création du mirroir
# `--` sert à séparer les opérations.
sudo ovs-vsctl -- set Bridge br-ares mirrors=@m -- --id=@m create Mirror name=mirroirSonde select_src_port=$UUID_SRV select_dst_port=$UUID_SRV output_port=$UUID_SND

echo "=== Vérificaiton du mirroir : "
if sudo ovs-vsctl find mirror name=mirroirSonde | grep -q .; then
    echo "Le mirror mirroirSonde existe"
else
    echo "Le mirror mirroirSonde n'existe pas"
fi

echo "=== 6. Exécution du Scénario de Test ==="

echo " -> Vérification de l'interface serveur..."
docker exec server ip link show veth-srv-cont

echo " -> Lancement du serveur Web Python en tâche de fond..."
docker exec -d server python3 -m http.server 80

echo " -> Lancement de la capture tcpdump sur la sonde..."
# On le lance en arrière-plan avec -d pour ne pas bloquer le script
# L'option -n de tcpdump empeche la résolution DNS
docker exec -d sonde tcpdump -i veth-snd-cont -n -w /data/capture_topology1.pcap
sleep 2

echo " -> Génération du trafic depuis le client..."
docker exec client curl -s http://10.0.0.2 > /dev/null
echo "Requête HTTP effectuée."

sleep 2 # Laisse le temps aux paquets d'être enregistrés

echo " -> Arrêt de la capture..."
# Trouver le PID de tcpdump dans le conteneur sonde et le tuer gracieusement
docker exec sonde kill -SIGTERM $(docker exec sonde pidof tcpdump) || true

echo "=== Terminé ! Le fichier de capture est disponible dans /home/debian/solution1/captures/ ==="

