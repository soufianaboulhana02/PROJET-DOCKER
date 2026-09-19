FROM debian:bullseye
#Ajout de rsh-server(serveur) et rsh-client(client)
RUN apt-get update && apt-get install -y \
    tcpdump \
    net-tools \
    iproute2 \
    rsh-client \
    rsh-server \ 
    procps \
    && apt-get clean


CMD ["sleep", "infinity"]
