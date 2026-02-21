#!/usr/bin/env bash

if [[ ! -e "/routeros/generate-dhcpd-conf.py" ]]; then

   cp -r /routeros_source/. /routeros
fi


cd /routeros

QEMU_BRIDGE_ETH1='qemubr1'
default_dev1='eth0'

# Optional env: guest NIC MAC (must match QEMU -nic mac=). Setting container
# eth0 to this MAC makes Docker bridge deliver replies to the VM to this port.
ROUTEROS_NIC_MAC="${ROUTEROS_NIC_MAC:-54:05:AB:CD:12:31}"

# Optional env: DNS servers for DHCP (space-separated). Passed to generate-dhcpd-conf.py.
ROUTEROS_DHCP_DNS="${ROUTEROS_DHCP_DNS:-8.8.8.8 8.8.4.4}"

# Optional env: set eth0 promisc on for bridge port (1 = on). Helps some setups
# with inter-container traffic when Docker bridge does not learn guest MAC.
ROUTEROS_ETH0_PROMISC="${ROUTEROS_ETH0_PROMISC:-1}"

# DHCPD must have an IP address to run, but that address doesn't have to
# be valid. This is the dummy address dhcpd is configured to use.
DUMMY_DHCPD_IP='10.0.0.1'

# These scripts configure/deconfigure the VM interface on the bridge.
QEMU_IFUP='/routeros/qemu-ifup'
QEMU_IFDOWN='/routeros/qemu-ifdown'

# The name of the dhcpd config file we make
DHCPD_CONF_FILE='/routeros/dhcpd.conf'

# First step, we run the things that need to happen before we start mucking
# with the interfaces. We start by generating the DHCPD config file based
# on our current address/routes. We "steal" the container's IP, and lease
# it to the VM once it starts up.
/routeros/generate-dhcpd-conf.py $QEMU_BRIDGE_ETH1 $ROUTEROS_DHCP_DNS >$DHCPD_CONF_FILE

function prepare_intf() {
   # First we clear out the IP address and route
   ip addr flush dev $1
   # Set container interface MAC to guest NIC MAC so Docker bridge associates
   # this port with the VM and delivers inter-container replies correctly.
   ip link set dev $1 address $ROUTEROS_NIC_MAC
   # Next, we create our bridge, and add our container interface to it.
   ip link add $2 type bridge
   ip link set dev $1 master $2
   # Then, we toggle the interface and the bridge to make sure everything is up
   # and running.
   ip link set dev $1 up
   ip link set dev $2 up
   # Optional promisc on eth0 so bridge port accepts all frames (helps when
   # Docker/bridge does not reliably learn guest MAC for inter-container).
   if [ "$ROUTEROS_ETH0_PROMISC" = "1" ]; then
      ip link set dev $1 promisc on
   fi
}

prepare_intf $default_dev1 $QEMU_BRIDGE_ETH1
# Finally, start our DHCPD server
udhcpd -I $DUMMY_DHCPD_IP -f $DHCPD_CONF_FILE &

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

# And run the VM! A brief explanation of the options here:
# -enable-kvm: Use KVM for this VM (much faster for our case).
# -nographic: disable SDL graphics.
# -serial mon:stdio: use "monitored stdio" as our serial output.
# -nic: Use a TAP interface with our custom up/down scripts.
# -drive: The VM image we're booting.
# mac: Set up your own interfaces mac addresses here, cause from winbox you can not change these later.
exec qemu-system-x86_64 \
   -serial mon:stdio \
   -nographic \
   -m 512 \
   -smp 4,sockets=1,cores=4,threads=1 \
   -cpu $CPU_FEATURES  \
   $KVM_OPTS \
   -nic tap,id=qemu1,mac=$ROUTEROS_NIC_MAC,script=$QEMU_IFUP,downscript=$QEMU_IFDOWN \
   "$@" \
   -hda $ROUTEROS_IMAGE
