FROM debian:stable-slim

RUN apt-get update && apt-get install -y \
    iputils-ping \
    curl \
    dnsutils \
    iproute2 \
    net-tools \
    traceroute \
    procps \
 && apt-get clean

CMD ["sleep", "infinity"]

