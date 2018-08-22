# Mikrotik RouterOS in Docker

## How to use

Build from `Dockerfile`

    docker build . --tag ros
    docker run -p 2222:22 -p 5900:5900 -ti ros

Now you can connecto to your RouterOS container via VNC protocol
and via SSH on localhost 2222 port.
