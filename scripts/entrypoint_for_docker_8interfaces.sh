#!/usr/bin/env bash

# This is a humble fork modification to the master work from EvilFreelancer
# These entrypoint is for maximum 8 interfaces using Docker virtual networks
# (need 8 custom bridge networks in docker)
# First qemubr1 use DHCP as EvilFreelancer did
# next 7 interfaces qemu neeed you set 7 fixed ip address in winbox
# you must create before 8 networks in your docker and attach to the container
# Also I have enabled 4 cores in the qemu vm
# Only for testing purpose or use in lab, please dont use in production
# this router has a free license - 1Mbps only
# I have tested and it is working great anyway
# It needs some help with the DRY if you have the time please fork 
# regards # lcchatter #

QEMU_BRIDGE_ETH1='qemubr1'
QEMU_BRIDGE_ETH2='qemubr2'
QEMU_BRIDGE_ETH3='qemubr3'
QEMU_BRIDGE_ETH4='qemubr4'
QEMU_BRIDGE_ETH5='qemubr5'
QEMU_BRIDGE_ETH6='qemubr6'
QEMU_BRIDGE_ETH7='qemubr7'
QEMU_BRIDGE_ETH8='qemubr8'
default_dev1='eth0'
default_dev2='eth1'
default_dev3='eth2'
default_dev4='eth3'
default_dev5='eth4'
default_dev6='eth5'
default_dev7='eth6'
default_dev8='eth7'
# DHCPD must have an IP address to run, but that address doesn't have to
# be valid. This is the dummy address dhcpd is configured to use.
DUMMY_DHCPD_IP='10.0.0.1'

# These scripts configure/deconfigure the VM interface on the bridge.

QEMU_IFUP='/routeros/qemu-ifup'
QEMU_IFDOWN='/routeros/qemu-ifdown'
QEMU_IFUP2='/routeros/qemu-ifup2'
QEMU_IFDOWN2='/routeros/qemu-ifdown2'
QEMU_IFUP3='/routeros/qemu-ifup3'
QEMU_IFDOWN3='/routeros/qemu-ifdown3'
QEMU_IFUP4='/routeros/qemu-ifup4'
QEMU_IFDOWN4='/routeros/qemu-ifdown4'
QEMU_IFUP5='/routeros/qemu-ifup5'
QEMU_IFDOWN5='/routeros/qemu-ifdown5'
QEMU_IFUP6='/routeros/qemu-ifup6'
QEMU_IFDOWN6='/routeros/qemu-ifdown6'
QEMU_IFUP7='/routeros/qemu-ifup7'
QEMU_IFDOWN7='/routeros/qemu-ifdown7'
QEMU_IFUP8='/routeros/qemu-ifup8'
QEMU_IFDOWN8='/routeros/qemu-ifdown8'

# The name of the dhcpd config file we make
DHCPD_CONF_FILE='/routeros/dhcpd.conf'
# function default_intf() {
#     ip -json route show | jq -r '.[] | select(.dst == "default") | .dev'
# }

# First step, we run the things that need to happen before we start mucking
# with the interfaces. We start by generating the DHCPD config file based
# on our current address/routes. We "steal" the container's IP, and lease
# it to the VM once it starts up.
/routeros/generate-dhcpd-conf.py $QEMU_BRIDGE_ETH1 >$DHCPD_CONF_FILE

function prepare_intf() {
   #First we clear out the IP address and route
   ip addr flush dev $1
   # Next, we create our bridge, and add our container interface to it.
   ip link add $2 type bridge
   ip link set dev $1 master $2
   # Then, we toggle the interface and the bridge to make sure everything is up
   # and running.
   ip link set dev $1 up
   ip link set dev $2 up
}

prepare_intf $default_dev1 $QEMU_BRIDGE_ETH1
# Finally, start our DHCPD server
udhcpd -I $DUMMY_DHCPD_IP -f $DHCPD_CONF_FILE &
prepare_intf $default_dev2 $QEMU_BRIDGE_ETH2
prepare_intf $default_dev3 $QEMU_BRIDGE_ETH3
prepare_intf $default_dev4 $QEMU_BRIDGE_ETH4
prepare_intf $default_dev5 $QEMU_BRIDGE_ETH5
prepare_intf $default_dev6 $QEMU_BRIDGE_ETH6
prepare_intf $default_dev7 $QEMU_BRIDGE_ETH7
prepare_intf $default_dev8 $QEMU_BRIDGE_ETH8

# And run the VM! A brief explanation of the options here:
# -enable-kvm: Use KVM for this VM (much faster for our case).
# -nographic: disable SDL graphics.
# -serial mon:stdio: use "monitored stdio" as our serial output.
# -nic: Use a TAP interface with our custom up/down scripts.
# -drive: The VM image we're booting.
# mac: Set up your own interfaces mac addresses here, cause from winbox you can not change these later.
exec qemu-system-x86_64 \
   -nographic -serial mon:stdio \
   -vnc 0.0.0.0:0 \
   -m 512 \
   -smp 4,sockets=1,cores=4,threads=1 \
   -nic tap,id=qemu1,mac=54:05:AB:CD:12:31,script=$QEMU_IFUP,downscript=$QEMU_IFDOWN \
   -nic tap,id=qemu2,mac=54:05:AB:CD:12:32,script=$QEMU_IFUP2,downscript=$QEMU_IFDOWN2 \
   -nic tap,id=qemu3,mac=54:05:AB:CD:12:33,script=$QEMU_IFUP3,downscript=$QEMU_IFDOWN3 \
   -nic tap,id=qemu4,mac=54:05:AB:CD:12:34,script=$QEMU_IFUP4,downscript=$QEMU_IFDOWN4 \
   -nic tap,id=qemu5,mac=54:05:AB:CD:12:35,script=$QEMU_IFUP5,downscript=$QEMU_IFDOWN5 \
   -nic tap,id=qemu6,mac=54:05:AB:CD:12:36,script=$QEMU_IFUP6,downscript=$QEMU_IFDOWN6 \
   -nic tap,id=qemu7,mac=54:05:AB:CD:12:37,script=$QEMU_IFUP7,downscript=$QEMU_IFDOWN7 \
   -nic tap,id=qemu8,mac=54:05:AB:CD:12:38,script=$QEMU_IFUP8,downscript=$QEMU_IFDOWN8 \
   "$@" \
   -hda $ROUTEROS_IMAGE
