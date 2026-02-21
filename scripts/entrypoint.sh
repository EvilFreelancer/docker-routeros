#!/usr/bin/env bash

if [[ ! -e "/routeros/generate-dhcpd-conf.py" ]]; then
   cp -r /routeros_source/. /routeros
fi


cd /routeros

ROUTEROS_DATA_DIR="${ROUTEROS_DATA_DIR:-/data}"
NIC_MAC_FILE="$ROUTEROS_DATA_DIR/nic_mac"

generate_nic_mac() {
   local hex
   hex=$(od -A n -N 6 -t x1 /dev/urandom 2>/dev/null | tr -d ' \n')
   if [ -z "$hex" ] || [ ${#hex} -lt 12 ]; then
      printf '52:%02x:%02x:%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))
      return
   fi
   local b0=$(( (0x${hex:0:2} & 0xFE) | 0x02 ))
   printf '%02x:%s:%s:%s:%s:%s' "$b0" "${hex:2:2}" "${hex:4:2}" "${hex:6:2}" "${hex:8:2}" "${hex:10:2}"
}

if [ -r "$NIC_MAC_FILE" ] && [ -s "$NIC_MAC_FILE" ]; then
   ROUTEROS_NIC_MAC=$(tr -d '\n\r' < "$NIC_MAC_FILE")
else
   ROUTEROS_NIC_MAC="${ROUTEROS_NIC_MAC:-$(generate_nic_mac)}"
   if [ -d "$ROUTEROS_DATA_DIR" ] && [ -w "$ROUTEROS_DATA_DIR" ]; then
      printf '%s\n' "$ROUTEROS_NIC_MAC" > "$NIC_MAC_FILE"
   fi
fi

QEMU_BRIDGE='qemubr1'
ROUTEROS_DHCP_DNS="${ROUTEROS_DHCP_DNS:-8.8.8.8 8.8.4.4}"
ROUTEROS_ETH_PROMISC="${ROUTEROS_ETH_PROMISC:-1}"

# When eth1 exists (container on two networks), use it for bridge so eth0 keeps IP for host port mapping.
if ip link show eth1 &>/dev/null; then
   BRIDGE_IF='eth1'
   USE_HOSTFWD=1
else
   BRIDGE_IF='eth0'
   USE_HOSTFWD=0
fi

DUMMY_DHCPD_IP='10.0.0.1'
QEMU_IFUP='/routeros/qemu-ifup'
QEMU_IFDOWN='/routeros/qemu-ifdown'
DHCPD_CONF_FILE='/routeros/dhcpd.conf'

/routeros/generate-dhcpd-conf.py $QEMU_BRIDGE --addr-from "$BRIDGE_IF" $ROUTEROS_DHCP_DNS >$DHCPD_CONF_FILE

function prepare_intf() {
   ip addr flush dev $1
   ip link set dev $1 address $ROUTEROS_NIC_MAC
   ip link add $2 type bridge
   ip link set dev $1 master $2
   ip link set dev $1 up
   ip link set dev $2 up
   if [ "$ROUTEROS_ETH_PROMISC" = "1" ]; then
      ip link set dev $1 promisc on
   fi
}

prepare_intf "$BRIDGE_IF" $QEMU_BRIDGE
udhcpd -I $DUMMY_DHCPD_IP -f $DHCPD_CONF_FILE &

QEMU_NIC_USER="user,hostfwd=tcp::22-:22,hostfwd=tcp::23-:23,hostfwd=tcp::80-:80,hostfwd=tcp::443-:443,hostfwd=tcp::8728-:8728,hostfwd=tcp::8729-:8729,hostfwd=tcp::8291-:8291,hostfwd=tcp::5900-:5900,hostfwd=tcp::21-:21,hostfwd=tcp::1194-:1194,hostfwd=tcp::1701-:1701,hostfwd=tcp::1723-:1723,hostfwd=udp::500-:500,hostfwd=udp::4500-:4500,hostfwd=udp::1812-:1812,hostfwd=udp::1813-:1813"

CPU_FEATURES=""
KVM_OPTS=""
if [ -e /dev/kvm ]; then
   if grep -q -e vmx -e svm /proc/cpuinfo; then
      echo "Enabling KVM"
      CPU_FEATURES="host,kvm=on"
      KVM_OPTS="-machine accel=kvm -enable-kvm"
   fi
fi

if [ "$CPU_FEATURES" = "" ]; then
   echo "KVM not available, running in emulation mode. This will be slow."
   CPU_FEATURES="qemu64"
fi

DISK_TO_USE="/routeros/$ROUTEROS_IMAGE"
# Second disk: raw file in data dir (created if missing). Size via ROUTEROS_DISK2_SIZE (default 256M)
ROUTEROS_DISK2_FILE="${ROUTEROS_DATA_DIR}/disk2.raw"
ROUTEROS_DISK2_SIZE="${ROUTEROS_DISK2_SIZE:-256M}"

run_qemu() {
   local DRIVES=(-hda "$DISK_TO_USE")

   if [ -n "$ROUTEROS_DATA_DIR" ] && [ -d "$ROUTEROS_DATA_DIR" ] && [ -w "$ROUTEROS_DATA_DIR" ]; then
      if [ ! -f "$ROUTEROS_DISK2_FILE" ]; then
         truncate -s "$ROUTEROS_DISK2_SIZE" "$ROUTEROS_DISK2_FILE" || true
      fi
      if [ -f "$ROUTEROS_DISK2_FILE" ]; then
         DRIVES+=(-drive "file=$ROUTEROS_DISK2_FILE,format=raw,if=ide,index=1,media=disk")
         echo "Second disk (hdb): $ROUTEROS_DISK2_FILE"
      fi
   fi

   local NIC_OPTS=()
   if [ "$USE_HOSTFWD" = "1" ]; then
      NIC_OPTS+=(-nic "$QEMU_NIC_USER" -nic "tap,id=qemu1,mac=$ROUTEROS_NIC_MAC,script=$QEMU_IFUP,downscript=$QEMU_IFDOWN")
   else
      NIC_OPTS+=(-nic "tap,id=qemu1,mac=$ROUTEROS_NIC_MAC,script=$QEMU_IFUP,downscript=$QEMU_IFDOWN")
   fi
   exec qemu-system-x86_64 \
      -serial mon:stdio \
      -nographic \
      -m 512 \
      -smp 4,sockets=1,cores=4,threads=1 \
      -cpu $CPU_FEATURES \
      $KVM_OPTS \
      "${NIC_OPTS[@]}" \
      "${DRIVES[@]}" \
      "$@"
}

run_qemu "$@"
