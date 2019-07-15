#!/bin/sh

qemu-system-x86_64 \
    -vnc 0.0.0.0:0 \
    -m 256 \
    -hda $ROUTEROS_IMAGE \
    -device e1000,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::21-:21,hostfwd=tcp::22-:22,hostfwd=tcp::23-:23,hostfwd=tcp::80-:80,hostfwd=tcp::443-:443,hostfwd=tcp::8291-:8291,hostfwd=tcp::8728-:8728,hostfwd=tcp::8729-:8729 \
    -device e1000,netdev=net1 \
    -netdev user,id=net1 \
    -device e1000,netdev=net2 \
    -netdev user,id=net2 \
    -device e1000,netdev=net3 \
    -netdev user,id=net3
