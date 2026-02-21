# MikroTik RouterOS in Docker

This project provides a Docker image that runs a MikroTik RouterOS
virtual machine inside QEMU.

It is designed to simulate a MikroTik RouterOS environment and is useful
for development and testing, especially when working with the RouterOS API.

The image is well-suited for unit testing the
[routeros-api-php](https://github.com/EvilFreelancer/routeros-api-php) library in a controlled
environment that closely mimics a real RouterOS setup.

For a production-ready RouterOS environment in Docker, consider the
[VR Network Lab](https://github.com/plajjan/vrnetlab) project as an alternative.

## Getting Started

### Pulling the Image from Docker Hub

Pull and run the image (optionally pin to a [RouterOS version tag](https://hub.docker.com/r/evilfreelancer/docker-routeros/tags/)):

```bash
docker pull evilfreelancer/docker-routeros
docker run -d -p 2222:22 -p 8728:8728 -p 8729:8729 -p 5900:5900 -ti evilfreelancer/docker-routeros
```

Ports are exposed for SSH, API, API-SSL, and VNC.

### Use in `docker-compose.yml`

For those preferring Docker Compose, an example is below. More examples are in
[docker-compose.dist.yml](docker-compose.dist.yml).

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

To build the image from source (e.g. for a specific RouterOS version):

```bash
git clone https://github.com/EvilFreelancer/docker-routeros.git
cd docker-routeros
docker build --build-arg ROUTEROS_VERSION=7.16 --tag ros .
docker run -d -p 2222:22 -p 8728:8728 -p 8729:8729 -p 5900:5900 -ti ros
```

Replace `7.16` with the desired [RouterOS version](https://mikrotik.com/download/archive). After starting the container, access RouterOS via VNC (port 5900) or SSH (port 2222).

### How Images Are Published (CI)

GitHub Actions runs on a schedule and on manual trigger. Only **stable** releases are considered (RC, alpha, beta are ignored). It:

1. Reads the latest stable RouterOS version from the [MikroTik download archive](https://mikrotik.com/download/archive) (e.g. `7.16.1`).
2. Fetches all existing tags for this image from Docker Hub (with pagination).
3. If that exact version is **missing** on Docker Hub: builds the image for `linux/amd64` and `linux/arm64`, then pushes tags:
   - `7.16.1` (exact version)
   - `7.16` (major.minor)
   - `7` (major)
   - `latest`
4. If that version **already exists**: updates the moving tags so that `7.16`, `7`, and `latest` point to this image (no rebuild).

So `latest` and major / major.minor tags always follow the newest stable RouterOS.

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

* [MikroTik RouterOS in Docker using QEMU](https://habr.com/ru/articles/498012/) (Habr) - Setup guide for RouterOS in Docker with QEMU.
* [RouterOS API Client](https://github.com/EvilFreelancer/routeros-api-php) - PHP library for the RouterOS API.
* [VR Network Lab](https://github.com/vrnetlab/vrnetlab) - Run network equipment in Docker; alternative for production-like RouterOS.
* [qemu-docker](https://github.com/joshkunz/qemu-docker) - QEMU in Docker.
* [QEMU/KVM on Docker](https://github.com/ennweb/docker-kvm) - QEMU/KVM virtualization in Docker.
