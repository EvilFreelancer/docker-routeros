FROM alpine:3.8

ENV ROUTEROS_VERSON="6.43.5"
ENV ROUTEROS_IMAGE="chr-$ROUTEROS_VERSON.vdi"
ENV ROUTEROS_PATH="https://download.mikrotik.com/routeros/$ROUTEROS_VERSON/$ROUTEROS_IMAGE"

RUN mkdir /routeros
WORKDIR /routeros
ADD [".", "/routeros"]

RUN apk add --no-cache --update netcat-openbsd qemu-x86_64 qemu-system-x86_64 \
 && echo ">>> $ROUTEROS_PATH" \
 && if [ ! -e "$ROUTEROS_IMAGE" ]; then wget "$ROUTEROS_PATH"; fi

# For access via VNC
EXPOSE 5900

# Default ports of RouterOS
EXPOSE 21
EXPOSE 22
EXPOSE 23
EXPOSE 80
EXPOSE 443
EXPOSE 8291
EXPOSE 8728
EXPOSE 8729

ENTRYPOINT ["/routeros/entrypoint.sh"]
