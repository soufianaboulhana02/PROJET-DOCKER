FROM debian:stable-slim

RUN apt-get update && apt-get install -y \
    tcpdump \
    iproute2 \
    net-tools \
 && apt-get clean

RUN mkdir -p /data
