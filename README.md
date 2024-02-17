# Mikrotik RouterOS in Docker

This project comprises a Docker image that runs a MikroTik's RouterOS
virtual machine inside QEMU.

It's designed to simulate MikroTik's RouterOS environment, making it an
excellent tool for development and testing purposes, especially for those
working with the RouterOS API.

This Docker image is particularly useful for unit testing the
[routeros-api-php](https://github.com/EvilFreelancer/routeros-api-php) library, allowing developers to test applications
in a controlled environment that closely mimics a real RouterOS setup.

For users seeking a fully operational RouterOS environment for production
use within Docker, the [VR Network Lab](https://github.com/plajjan/vrnetlab) project is recommended
as an alternative.

## Getting Started

### Pulling the Image from Docker Hub

To use the image directly from Docker Hub, you can pull it and run a
container as shown below. This will start a RouterOS instance with ports
configured for SSH, API, API-SSL, and VNC access.

```bash
docker pull evilfreelancer/docker-routeros
docker run -d -p 2222:22 -p 8728:8728 -p 8729:8729 -p 5900:5900 -ti evilfreelancer/docker-routeros
```

### Use in `docker-compose.yml`

For those preferring docker-compose, an example configuration is provided
below. More examples is [here](docker-compose.dist.yml).

```yml
version: "3.9"
services:
  routeros:
    image: evilfreelancer/docker-routeros:latest
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
      - /dev/kvm
    ports:
      - "2222:22"
      - "23:23"
      - "80:80"
      - "5900:5900"
      - "8728:8728"
      - "8729:8729"
```

### Creating a Custom `Dockerfile`

You can easily create your own Dockerfile to include custom scripts or
configurations. The Docker image supports various tags, which are listed
[here](https://hub.docker.com/r/evilfreelancer/docker-routeros/tags/).
By default, the `latest` tag is used if no tag is specified.

```dockerfile
FROM evilfreelancer/docker-routeros
ADD ["your-scripts.sh", "/"]
RUN /your-scripts.sh
```

### Building from Source

If you prefer to build the Docker image from source, the commands below
will guide you through cloning the repository, building the image, and
running a RouterOS container.

```bash
git clone https://github.com/EvilFreelancer/docker-routeros.git
cd docker-routeros
docker build . --tag ros
docker run -d -p 2222:22 -p 8728:8728 -p 8729:8729 -p 5900:5900 -ti ros
```

After launching the container, you can access your RouterOS instance
via VNC (port 5900) and SSH (port 2222).

## Exposed Ports

The table below summarizes the ports exposed by the Docker image,
catering to various services and protocols used by RouterOS.

| Description | Ports                                 |
|-------------|---------------------------------------|
| Defaults    | 21, 22, 23, 80, 443, 8291, 8728, 8729 |
| IPSec       | 50, 51, 500/udp, 4500/udp             |
| OpenVPN     | 1194/tcp, 1194/udp                    |
| L2TP        | 1701                                  |
| PPTP        | 1723                                  |

## Links

For more insights into Docker and virtualization technologies
related to RouterOS and networking, explore the following resources:

* [Mikrotik RouterOS in Docker using Qemu](https://habr.com/ru/articles/498012/) - An article on Habr that provides a guide on setting up Mikrotik RouterOS in Docker using Qemu, ideal for developers and network engineers interested in RouterOS virtualization.
* [RouterOS API Client](https://github.com/EvilFreelancer/routeros-api-php) - GitHub repository for the RouterOS API PHP library, useful for interfacing with MikroTik devices.
* [VR Network Lab](https://github.com/vrnetlab/vrnetlab) - A project for running network equipment in Docker containers, recommended for production-level RouterOS simulations.
* [qemu-docker](https://github.com/joshkunz/qemu-docker) - A resource for integrating QEMU with Docker, enabling virtual machine emulation within containers.
* [QEMU/KVM on Docker](https://github.com/ennweb/docker-kvm) - Demonstrates using QEMU/KVM virtualization within Docker containers for improved performance.
