FROM alpine:3.11

# For access via VNC
EXPOSE 5900

# Default ports of RouterOS
EXPOSE 21 22 23 80 443 8291 8728 8729

# Different VPN services
EXPOSE 50 51 500/udp 4500/udp 1194/tcp 1194/udp 1701 1723

# Change work dir (it will also create this folder if is not exist)
WORKDIR /routeros

# Install dependencies
RUN set -xe \
 && apk add --no-cache --update \
    netcat-openbsd qemu-x86_64 qemu-system-x86_64 \
    busybox-extras iproute2 iputils \
    bridge-utils iptables jq bash python3

# Environments which may be change
ENV ROUTEROS_VERSON="6.48beta58"
ENV ROUTEROS_IMAGE="chr-$ROUTEROS_VERSON.vdi"
ENV ROUTEROS_PATH="https://download.mikrotik.com/routeros/$ROUTEROS_VERSON/$ROUTEROS_IMAGE"

# Download VDI image from remote site
RUN wget "$ROUTEROS_PATH" -O "/routeros/$ROUTEROS_IMAGE"

# Copy script to routeros folder
ADD ["./scripts", "/routeros"]

ENTRYPOINT ["/routeros/entrypoint.sh"]
