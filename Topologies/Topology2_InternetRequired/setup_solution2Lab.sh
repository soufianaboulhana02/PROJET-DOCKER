#!/bin/bash

# Arrêt du script en cas d'erreur
set -e

echo "=== 0. Nettoyage de l'environnement (Clean State) ==="
echo " -> Nettoyage des conteneurs (incluant le routeur)..."
docker rm -f server client sonde router 2>/dev/null || true

echo " -> Nettoyage du réseau Docker..."
docker network rm net-ares 2>/dev/null || true

echo " -> Nettoyage d'Open vSwitch (OVS)..."
# La suppression du bridge détruit automatiquement la config SPAN et les tags VLAN
sudo ovs-vsctl del-br br-ares 2>/dev/null || true

echo " -> Nettoyage des interfaces virtuelles orphelines..."
sudo ip link delete veth-srv-host 2>/dev/null || true
sudo ip link delete veth-clt-host 2>/dev/null || true
sudo ip link delete veth-snd-host 2>/dev/null || true
sudo ip link delete veth-rt1-host 2>/dev/null || true
sudo ip link delete veth-rt2-host 2>/dev/null || true

echo "=== 1. Préparation de l'hôte et vérification d'Open vSwitch ==="

# Vérification silencieuse de l'installation du paquet
if ! dpkg -s openvswitch-switch >/dev/null 2>&1; then
    echo " -> Le paquet openvswitch-switch n'est pas installé. Installation en cours..."
    sudo apt update -qq && sudo apt install -y openvswitch-switch
else
    echo " -> Le paquet openvswitch-switch est déjà installé. Maintien de la configuration."
fi

# Création du Switch OVS
sudo ovs-vsctl add-br br-ares 2>/dev/null || true
sudo ip link set br-ares up  # activer l'OVS


echo "=== 2. Lancement de l'infrastructure Docker ==="
docker compose up -d # lancement conteneurs en detach mode


echo "=== 3. Installation des dépendances dans les conteneurs ==="
# L'option -qq pour réduire au maximum affichage des messages
# Note : FRRouting embarque déjà les outils réseau nécessaires nativement
docker exec server apt update -qq && docker exec server apt install -y -qq procps iproute2 python3
docker exec client apt update -qq && docker exec client apt install -y -qq iputils-ping curl
docker exec sonde apt update -qq && docker exec sonde apt install -y -qq tcpdump procps


echo "=== 4. Câblage réseau OVS (VLANs, Veth Pairs & Namespaces) ==="

# Fonction générique améliorée pour connecter un conteneur à OVS avec gestion des VLANs
connect_to_ovs() {
        local CONTAINER=$1
        local IP_ADDR=$2
        local PREFIX=$3
        local INT_CONT=$4  # Nom de l'interface dans le conteneur (ex: veth-srv-cont ou eth1)
        local TAG=$5       # Tag VLAN (optionnel)

        local V_HOST="veth-${PREFIX}-host"

        echo "Connexion de $CONTAINER via $V_HOST / $INT_CONT (VLAN: ${TAG:-Aucun})..."

        # Nettoyage d'anciennes interfaces si elles existent
        sudo ip link delete $V_HOST 2>/dev/null || true

        # Créer la paire veth
        sudo ip link add $V_HOST type veth peer name $INT_CONT
        
        # Attacher veth host à OVS (avec application du Tag VLAN si spécifié)
        if [ -n "$TAG" ]; then
            sudo ovs-vsctl add-port br-ares $V_HOST tag=$TAG
        else
            sudo ovs-vsctl add-port br-ares $V_HOST
        fi

        # Récupérer PID du conteneur
        local PID=$(docker inspect -f '{{.State.Pid}}' $CONTAINER)
        # Attacher le namespace réseau du conteneur au veth conteneur
        sudo ip link set $INT_CONT netns $PID

        # Mettre veth conteneur en up et lui affecter une IP (si une IP est fournie)
        sudo nsenter -t $PID -n ip link set $INT_CONT up
        if [ -n "$IP_ADDR" ]; then
            sudo nsenter -t $PID -n ip addr add $IP_ADDR dev $INT_CONT
        fi

        # Mettre veth host en up
        sudo ip link set $V_HOST up
}

# --- Câblage des machines terminales ---
connect_to_ovs "client" "10.1.10.2/24" "clt" "veth-clt-cont" "10"
connect_to_ovs "server" "10.1.20.2/24" "srv" "veth-srv-cont" "20"
connect_to_ovs "sonde" "" "snd" "veth-snd-cont" "" # La sonde n'a pas besoin d'IP ni de VLAN

# --- Câblage du Routeur FRR (Une patte dans chaque VLAN) ---
connect_to_ovs "router" "10.1.10.1/24" "rt1" "eth1" "10"
connect_to_ovs "router" "10.1.20.1/24" "rt2" "eth2" "20"


echo " -> Configuration du routage par défaut sur les hôtes..."
PID_CLT=$(docker inspect -f '{{.State.Pid}}' client)
PID_SRV=$(docker inspect -f '{{.State.Pid}}' server)
# Remplacement de la route par défaut de Docker pour forcer le passage par notre routeur FRR
sudo nsenter -t $PID_CLT -n ip route replace default via 10.1.10.1
sudo nsenter -t $PID_SRV -n ip route replace default via 10.1.20.1

echo "=== 5. Configuration du Port Mirroring (SPAN) sur OVS ==="
# Récupération dynamique des UUIDs
UUID_SRV=$(sudo ovs-vsctl get port veth-srv-host _uuid)
UUID_SND=$(sudo ovs-vsctl get port veth-snd-host _uuid)

# Suppression d'un ancien miroir éventuel, puis création du nouveau
sudo ovs-vsctl -- --id=@m get Mirror mirroirSonde 2>/dev/null && sudo ovs-vsctl -- clear Bridge br-ares mirrors || true

# TOUT ceci représente une seule commande de création du miroir
# `--` sert à séparer les opérations.
sudo ovs-vsctl -- set Bridge br-ares mirrors=@m \
  -- --id=@m create Mirror name=mirroirSonde \
  select_src_port=$UUID_SRV \
  select_dst_port=$UUID_SRV \
  output_port=$UUID_SND

echo "=== Vérification du miroir : "
if sudo ovs-vsctl find mirror name=mirroirSonde | grep -q .; then
    echo "Le mirror mirroirSonde existe"
else
    echo "Le mirror mirroirSonde n'existe pas"
fi


echo "=== 6. Exécution du Scénario de Test (Routage Inter-VLAN) ==="

echo " -> Lancement du serveur Web Python en tâche de fond sur le Serveur (VLAN 20)..."
docker exec -d server python3 -m http.server 80

echo " -> Lancement de la capture tcpdump sur la sonde..."
# On le lance en arrière-plan avec -d pour ne pas bloquer le script
docker exec -d sonde tcpdump -i veth-snd-cont -n -w /data/capture_topology2.pcap
sleep 2

echo " -> Génération du trafic HTTP depuis le Client (VLAN 10) vers le Serveur (VLAN 20)..."
docker exec client curl -s http://10.1.20.2 > /dev/null
echo "Requête HTTP effectuée avec succès à travers le routeur FRR."

sleep 2 # Laisse le temps aux paquets d'être enregistrés

echo " -> Arrêt de la capture..."
# Trouver le PID de tcpdump dans le conteneur sonde et le tuer gracieusement
docker exec sonde kill -SIGTERM $(docker exec sonde pidof tcpdump) || true

echo "=== Terminé ! Le fichier de capture est disponible dans /home/debian/solution2/captures/capture_phase2.pcap ==="
