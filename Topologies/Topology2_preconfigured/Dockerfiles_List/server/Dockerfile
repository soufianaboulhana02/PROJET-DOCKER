FROM debian:stable-slim

RUN apt-get update && apt-get install -y \
    python3 \
    iproute2 \
    net-tools \
 && apt-get clean

WORKDIR /app
RUN echo "<h1>docker lab server<h2>" > index.html
CMD ["python3", "-m", "http.server", "80"]



