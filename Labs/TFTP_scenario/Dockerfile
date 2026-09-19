FROM debian:latest
#Ajout de tftpd-hpa (serveur) et tftp(client)
RUN apt-get update && apt-get install -y \
    tcpdump \
    net-tools \
    iproute2 \
    tftpd-hpa \
    tftp-hpa \ 
    procps \
    && apt-get clean


CMD ["sleep", "infinity"]
