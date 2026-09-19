#!/bin/bash

set -e

echo "=== 0. Nettoyage ==="
docker rm -f server client sonde router1 router2 2>/dev/null || true
docker network rm net-ares 2>/dev/null || true

sudo ovs-vsctl del-br br-ares 2>/dev/null || true

sudo ip link delete veth-srv-host 2>/dev/null || true
sudo ip link delete veth-clt-host 2>/dev/null || true
sudo ip link delete veth-snd-host 2>/dev/null || true
sudo ip link delete veth-r1-10-host 2>/dev/null || true
sudo ip link delete veth-r1-30-host 2>/dev/null || true
sudo ip link delete veth-r2-20-host 2>/dev/null || true
sudo ip link delete veth-r2-30-host 2>/dev/null || true

echo "=== 1. OVS ==="
sudo ovs-vsctl add-br br-ares 2>/dev/null || true
sudo ip link set br-ares up

echo "=== 2. Lancement Docker ==="
docker compose up -d

echo "=== 2.5 Isolement Strict (Pur SDN) ==="
docker network disconnect net-ares router1 2>/dev/null || true
docker network disconnect net-ares router2 2>/dev/null || true

# Fonction générique de câblage améliorée avec gestion explicite des adresses MAC
connect_to_ovs() {
        local CONTAINER=$1
        local IP_ADDR=$2
        local PREFIX=$3
        local INT_CONT=$4  
        local TAG=$5       
        local MAC_ADDR=$6  # NOUVEAU: Forçage de l'adresse MAC

        local V_HOST="veth-${PREFIX}-host"

        echo "Connexion de $CONTAINER via $V_HOST / $INT_CONT (VLAN: ${TAG:-Aucun}) [MAC: $MAC_ADDR]..."

        sudo ip link delete $V_HOST 2>/dev/null || true
        sudo ip link add $V_HOST type veth peer name $INT_CONT

        sudo sysctl -w net.ipv4.conf.$V_HOST.proxy_arp=0 >/dev/null 2>&1 || true
        sudo sysctl -w net.ipv6.conf.$V_HOST.disable_ipv6=1 >/dev/null 2>&1 || true

        if [ -n "$TAG" ]; then
            sudo ovs-vsctl add-port br-ares $V_HOST tag=$TAG
        else
            sudo ovs-vsctl add-port br-ares $V_HOST
        fi

        local PID=$(docker inspect -f '{{.State.Pid}}' $CONTAINER)
        sudo ip link set $INT_CONT netns $PID

        # SECTION CRITIQUE : Assignation d'une MAC unique pour éviter les collisions OVS
        if [ -n "$MAC_ADDR" ]; then
            sudo nsenter -t $PID -n ip link set dev $INT_CONT address $MAC_ADDR
        fi

        sudo nsenter -t $PID -n ip link set lo up 2>/dev/null || true
        sudo nsenter -t $PID -n ip link set $INT_CONT up
        if [ -n "$IP_ADDR" ]; then
            sudo nsenter -t $PID -n ip addr add $IP_ADDR dev $INT_CONT
        fi

        sudo ip link set $V_HOST up
}

echo "=== 3. Câblage Réseau (3 VLANs + MACs déterministes) ==="
connect_to_ovs "client" "10.1.10.2/24" "clt" "veth-clt-cont" "10" "02:00:00:00:00:10"
connect_to_ovs "server" "10.1.20.2/24" "srv" "veth-srv-cont" "20" "02:00:00:00:00:20"
connect_to_ovs "sonde" "" "snd" "veth-snd-cont" "" "02:00:00:00:00:99"

connect_to_ovs "router1" "10.1.10.1/24" "r1-10" "eth1" "10" "02:00:00:00:01:10"
connect_to_ovs "router1" "10.1.30.1/24" "r1-30" "eth2" "30" "02:00:00:00:01:30"

connect_to_ovs "router2" "10.1.20.1/24" "r2-20" "eth1" "20" "02:00:00:00:02:20"
connect_to_ovs "router2" "10.1.30.2/24" "r2-30" "eth2" "30" "02:00:00:00:02:30"

echo "=== 4. Routes par défaut des hôtes ==="
PID_CLT=$(docker inspect -f '{{.State.Pid}}' client)
PID_SRV=$(docker inspect -f '{{.State.Pid}}' server)
sudo nsenter -t $PID_CLT -n ip route replace default via 10.1.10.1 dev veth-clt-cont
sudo nsenter -t $PID_SRV -n ip route replace default via 10.1.20.1 dev veth-srv-cont

echo "=== 5. Configuration du Routage Dynamique et Pare-feu ==="
for r in router1 router2; do
    # Activation du routage
    docker exec $r sysctl -w net.ipv4.ip_forward=1 > /dev/null
    docker exec $r sysctl -w net.ipv4.conf.all.rp_filter=0 > /dev/null
    docker exec $r sysctl -w net.ipv4.conf.default.rp_filter=0 > /dev/null
    
    # Éradication totale des règles Docker qui bloquent le trafic
    docker exec $r iptables -F
    docker exec $r iptables -X
    docker exec $r iptables -P FORWARD ACCEPT
    docker exec $r iptables -P INPUT ACCEPT
    docker exec $r iptables -P OUTPUT ACCEPT
    
    docker exec $r touch /etc/frr/vtysh.conf
done

# Configuration RIPv2 (Déclaration explicite des sous-réseaux)
docker exec router1 vtysh -c "configure terminal" \
    -c "router rip" \
    -c "version 2" \
    -c "timers basic 5 15 10" \
    -c "network 10.1.10.0/24" \
    -c "network 10.1.30.0/24" \
    -c "redistribute connected"

docker exec router2 vtysh -c "configure terminal" \
    -c "router rip" \
    -c "version 2" \
    -c "timers basic 5 15 10" \
    -c "network 10.1.20.0/24" \
    -c "network 10.1.30.0/24" \
    -c "redistribute connected"


echo "=== 6. Port Mirroring sur le réseau de Transit (VLAN 30) ==="
UUID_R1_TRS=$(sudo ovs-vsctl get port veth-r1-30-host _uuid)
UUID_SND=$(sudo ovs-vsctl get port veth-snd-host _uuid)

sudo ovs-vsctl clear Bridge br-ares mirrors 2>/dev/null || true
sudo ovs-vsctl -- \
--id=@m create Mirror name=mirroirTransit \
select-src-port=$UUID_R1_TRS \
select-dst-port=$UUID_R1_TRS \
output-port=$UUID_SND \
-- set Bridge br-ares mirrors=@m

echo "=== 7. Test de bout en bout ==="
echo " -> Lancement de la capture (tcpdump) sur la sonde..."
docker exec -d sonde tcpdump -i veth-snd-cont -n -U -w /data/capture_topology3_rip.pcap

echo " -> Attente de la convergence RIP accélérée (15 secondes)..."
sleep 15

echo " -> Ping du Client vers le Serveur (10 paquets)..."
docker exec client ping -c 10 10.1.20.2
sleep 2

echo " -> Traceroute du Client vers le Serveur..."
docker exec client traceroute -n 10.1.20.2
sleep 2

# Arrêt de la capture en masquant les erreurs si pkill n'est pas installé
docker exec sonde sh -c 'pkill tcpdump || kill $(pidof tcpdump)' >/dev/null 2>&1 || true

echo "=== FIN: Capture sauvegardée (capture_topology3_rip.pcap) ==="
