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
docker run -d -p 2222:22 -p 2223:23 -p 8728:8728 -p 8729:8729 -p 5900:5900 -ti evilfreelancer/docker-routeros
```

Ports are exposed for SSH (22), telnet (23), API (8728, 8729), and VNC (5900). Wait 30-60 seconds after start for RouterOS to boot, then connect e.g. `ssh -p 2222 admin@localhost` or `telnet localhost 2223`. For inter-container networking and more reliable host access, use Docker Compose with two networks (see below).

### Use in `docker-compose.yml`

Use **two networks** so that host port mapping (SSH, telnet, API) works reliably and the RouterOS guest is on a shared network with other containers. Copy [docker-compose.dist.yml](docker-compose.dist.yml) as a starting point.

```yml
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
      - "2223:23"
      - "8728:8728"
      - "8729:8729"
    volumes:
      - ./routeros_data:/data
    networks:
      - default
      - routeros_net

networks:
  routeros_net:
    driver: bridge
```

With two networks the container gets `eth0` (default) and `eth1` (routeros_net). The entrypoint leaves eth0 for host port mapping (QEMU forwards ports into the guest) and puts eth1 in a bridge so the VM gets an IP on `routeros_net` and can reach other containers. After the container starts, wait 30-60 seconds for RouterOS to boot, then connect via SSH (port 2222) or telnet (port 2223).

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

Replace `7.16` with the desired [RouterOS version](https://mikrotik.com/download/archive). After starting the container, wait 30-60 seconds for RouterOS to boot, then access via VNC (port 5900), SSH (port 2222), or telnet (port 2223).

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

## Networking modes

- **Two networks (recommended):** Attach the container to `default` and a shared network (e.g. `routeros_net`). The container gets eth0 and eth1. The entrypoint leaves **eth0** for host port mapping (QEMU user-mode networking with hostfwd), so SSH, telnet, API, Winbox from the host work. **eth1** is put in a bridge with the VM TAP; the guest gets an IP on the shared network via DHCP and can reach other containers (and the internet via Docker gateway). Use this when you need both host access and inter-container visibility.

- **Single network:** If the container has only one interface (eth0), it is put in the bridge and the VM gets the container IP via DHCP. Host port mapping then relies on the bridge forwarding to the VM; inter-container works. For reliable host access (SSH/telnet without hangs), prefer two networks.

**Two or more RouterOS on the same Docker network:** each container needs a unique MAC. By default a unique MAC is generated per volume and stored in `ROUTEROS_DATA_DIR/nic_mac`; use different volumes per service so each gets its own MAC. To set a MAC explicitly, use `ROUTEROS_NIC_MAC` or write it to `nic_mac` in the data dir.

### Example: two RouterOS + host access and inter-container

```yml
services:
  routeros:
    image: evilfreelancer/docker-routeros:latest
    restart: unless-stopped
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun", "/dev/kvm"]
    ports: ["2222:22", "2223:23", "8728:8728", "8729:8729"]
    volumes: ["./routeros_data:/data"]
    networks: [default, routeros_net]

  routeros2:
    image: evilfreelancer/docker-routeros:latest
    restart: unless-stopped
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun", "/dev/kvm"]
    ports: ["3222:22", "3223:23", "18728:8728", "18729:8729"]
    volumes: ["./routeros_data2:/data"]
    networks: [default, routeros_net]
    # Each volume gets its own MAC in nic_mac; no need to set ROUTEROS_NIC_MAC unless you want a fixed value.

networks:
  routeros_net:
    driver: bridge
```

Connect from host: `ssh -p 2222 admin@localhost` or `telnet localhost 2223`. From inside either RouterOS guest you can reach the other by service name (e.g. `routeros2`) or by its IP on `routeros_net`.

### Example: RouterOS and another service on one network

```yml
services:
  routeros:
    image: evilfreelancer/docker-routeros:latest
    restart: unless-stopped
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun", "/dev/kvm"]
    ports: ["2222:22", "2223:23", "8728:8728", "8729:8729"]
    volumes: ["./routeros_data:/data"]
    networks: [default, network1]

  other-service:
    image: your-image
    networks: [network1]

networks:
  network1:
    driver: bridge
```

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ROUTEROS_NIC_MAC` | (generated) | MAC of the guest NIC on the bridge (TAP). At start the value is read from `ROUTEROS_DATA_DIR/nic_mac` if the file exists; otherwise the env is used if set, else a unique MAC is generated and written to that file so it persists per volume. Set this env only to override the stored or generated value. |
| `ROUTEROS_DHCP_DNS` | `8.8.8.8 8.8.4.4` | Space-separated DNS servers passed to the guest via DHCP. |
| `ROUTEROS_ETH_PROMISC` | `1` | Set to `1` to enable promiscuous mode on the bridge port (eth0 or eth1). Set to `0` to disable. |
| `ROUTEROS_DATA_DIR` | `/data` | Folder in the container exposed to the VM as a FAT disk (VVFAT). Mount a Docker volume here so files are visible in RouterOS and persist. See "FAT disk from host folder" below. |

Example with custom DNS and MAC:

```yml
  routeros:
    image: evilfreelancer/docker-routeros:latest
    environment:
      ROUTEROS_NIC_MAC: "54:05:AB:CD:12:31"
      ROUTEROS_DHCP_DNS: "1.1.1.1 1.0.0.1"
      ROUTEROS_ETH_PROMISC: "1"
```

## FAT disk from host folder

You can expose a folder from the container (and thus a Docker volume) to the VM as a second disk in FAT format. Set `ROUTEROS_DATA_DIR` to that path (default `/data`) and mount a volume there. The VM will see it as a virtio disk; in RouterOS you can use it for scripts, backups, or any files that should persist when you change the image tag. The same directory is used to store the bridge NIC MAC in `nic_mac` (read at start; if missing, a unique MAC is generated or taken from `ROUTEROS_NIC_MAC` and written there) so each volume keeps a stable MAC.

Example:

```yml
  routeros-persistent:
    image: evilfreelancer/docker-routeros:latest
    restart: unless-stopped
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun", "/dev/kvm"]
    ports: ["32222:22", "32223:23", "38728:8728", "38729:8729"]
    volumes:
      - ./routeros_data:/data
    networks: [default, routeros_net]
```

Here `./routeros_data` is mounted at `/data` and exposed to the VM as a FAT disk. Two networks are used so host port mapping works reliably.

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
* [tenable/routeros](https://github.com/tenable/routeros) - RouterOS security research tooling and proof of concepts (Winbox, JSProxy, scanners, honeypots).
