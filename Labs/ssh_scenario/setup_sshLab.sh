#!/bin/bash

set -e

echo "=== 0. Nettoyage ==="
docker rm -f server client sonde router 2>/dev/null || true
docker network rm net-ares 2>/dev/null || true

sudo ovs-vsctl del-br br-ares 2>/dev/null || true

sudo ip link delete veth-srv-host 2>/dev/null || true
sudo ip link delete veth-clt-host 2>/dev/null || true
sudo ip link delete veth-snd-host 2>/dev/null || true
sudo ip link delete veth-rt1-host 2>/dev/null || true
sudo ip link delete veth-rt2-host 2>/dev/null || true

echo "=== 1. OVS ==="
sudo ovs-vsctl add-br br-ares 2>/dev/null || true
sudo ip link set br-ares up

echo "=== 2. Lancement Docker ==="
docker compose up -d

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

# --- machines ---
connect_to_ovs "client" "10.1.10.2/24" "clt" "veth-clt-cont" "10"
connect_to_ovs "server" "10.1.20.2/24" "srv" "veth-srv-cont" "20"
connect_to_ovs "sonde" "" "snd" "veth-snd-cont" ""

# --- routeur ---
connect_to_ovs "router" "10.1.10.1/24" "rt1" "eth1" "10"
connect_to_ovs "router" "10.1.20.1/24" "rt2" "eth2" "20"

echo "=== 4. Routes ==="

PID_CLT=$(docker inspect -f '{{.State.Pid}}' client)
PID_SRV=$(docker inspect -f '{{.State.Pid}}' server)

sudo nsenter -t $PID_CLT -n ip route replace default via 10.1.10.1
sudo nsenter -t $PID_SRV -n ip route replace default via 10.1.20.1

echo "=== 5. Mirroring ==="

UUID_SRV=$(sudo ovs-vsctl get port veth-srv-host _uuid)
UUID_SND=$(sudo ovs-vsctl get port veth-snd-host _uuid)

sudo ovs-vsctl clear Bridge br-ares mirrors 2>/dev/null || true

sudo ovs-vsctl -- \
--id=@m create Mirror name=mirroirSonde \
select-src-port=$UUID_SRV \
select-dst-port=$UUID_SRV \
output-port=$UUID_SND \
-- set Bridge br-ares mirrors=@m

echo "=== 6. Test ==="

echo "demarrage de service ssh sur le serveur "
docker exec -d server service ssh start
sleep 2
echo "Lancement de la capture sur la sonde"
docker exec -d sonde tcpdump -i veth-snd-cont -n -w /data/capture_ssh.pcap
sleep 2
echo "generation de trafic ssh depuis le client"
docker exec client sshpass -p "reseau" ssh -o StrictHostKeyChecking=no etudiant@10.1.20.2 echo "'Connexion etablie !' && ls -la"
sleep 2

docker exec sonde pkill tcpdump || true

echo "=== OK ==="
