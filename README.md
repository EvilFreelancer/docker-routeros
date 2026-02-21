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

### Supported platforms

The image is built for **linux/amd64** and **linux/arm64**. On Apple Silicon (M1/M2/M3) Docker will pull the arm64 image automatically. RouterOS CHR is x86_64 only; on arm64 the image runs RouterOS inside QEMU emulation (no KVM on Mac/ARM), so it may be slower than on amd64 with KVM.

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
      - /dev/kvm   # omit on Apple Silicon (no KVM there; container uses QEMU emulation)
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

To build for both amd64 and arm64 (e.g. for Apple Silicon and x86):

```bash
docker buildx create --use --name routeros_builder
docker buildx build --platform linux/amd64,linux/arm64 --build-arg ROUTEROS_VERSION=7.16 --tag ros .
```

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

## Inter-container networking (same Docker network + internet)

By default the entrypoint uses bridge + TAP so the RouterOS guest gets the container IP via DHCP and can reach the internet. To have the guest also reach other containers on the same Docker network (by IP or service name), the image does the following:

- Sets the container's eth0 MAC to the guest NIC MAC so the Docker bridge delivers replies to the VM to this port.
- Optionally enables promiscuous mode on eth0 (default on) so the bridge port accepts all frames if the bridge does not learn the guest MAC.

**Two or more RouterOS containers on the same Docker network:** each container must use a unique `ROUTEROS_NIC_MAC`, otherwise the bridge sees duplicate MACs and forwarding breaks. Set different MACs per service (e.g. `54:05:AB:CD:12:31`, `54:05:AB:CD:12:32`).

Example: RouterOS and another service on one network with a fixed subnet:

```yml
services:
  routeros:
    image: evilfreelancer/docker-routeros:6.48.1
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
      - /dev/kvm
    ports:
      - "18728:8728"
      - "18729:8729"
    networks:
      network1:

  other-service:
    image: your-image
    networks:
      network1:
        ipv4_address: 172.18.0.5

networks:
  network1:
    driver: bridge
    ipam:
      config:
        - subnet: 172.18.0.0/16
          gateway: 172.18.0.1
```

Example: two RouterOS containers on the same network (each needs a unique MAC):

```yml
services:
  routeros1:
    image: evilfreelancer/docker-routeros:latest
    environment:
      ROUTEROS_NIC_MAC: "54:05:AB:CD:12:31"
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun", "/dev/kvm"]
    networks: [network1]

  routeros2:
    image: evilfreelancer/docker-routeros:latest
    environment:
      ROUTEROS_NIC_MAC: "54:05:AB:CD:12:32"
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun", "/dev/kvm"]
    networks: [network1]

networks:
  network1:
    driver: bridge
```

Optional environment variables (stateless, no extra config files):

| Variable | Default | Description |
|----------|---------|-------------|
| `ROUTEROS_NIC_MAC` | `54:05:AB:CD:12:31` | Guest NIC MAC; must be unique per container when several RouterOS containers share one network. eth0 is set to this MAC so the Docker bridge delivers traffic to the VM. |
| `ROUTEROS_DHCP_DNS` | `8.8.8.8 8.8.4.4` | Space-separated DNS servers passed to the guest via DHCP. |
| `ROUTEROS_ETH0_PROMISC` | `1` | Set to `1` to enable promiscuous mode on eth0 (bridge port). Set to `0` to disable. |

Example with custom DNS and MAC:

```yml
  routeros:
    image: evilfreelancer/docker-routeros:latest
    environment:
      ROUTEROS_NIC_MAC: "54:05:AB:CD:12:31"
      ROUTEROS_DHCP_DNS: "1.1.1.1 1.0.0.1"
      ROUTEROS_ETH0_PROMISC: "1"
```

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
