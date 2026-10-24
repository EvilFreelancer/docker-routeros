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
docker run -d -p 127.0.0.1:8080:80 -p 2222:22 -p 2223:23 -p 8728:8728 -p 8729:8729 -p 5900:5900 -ti evilfreelancer/docker-routeros
```

This publishes WebFig (guest port 80) on `http://127.0.0.1:8080`, plus SSH (22), telnet (23), API (8728, 8729), and VNC (5900). Wait 30-60 seconds after start for RouterOS to boot; emulation without KVM can take longer. Then open WebFig or connect with `ssh -p 2222 admin@localhost`. A single Docker network is enough for published management ports. Use two networks when the guest also needs a TAP bridge to other containers (see below).

### Use in `docker-compose.yml`

Copy [docker-compose.dist.yml](docker-compose.dist.yml) as a starting point. This example uses **two networks** for published management ports and a TAP bridge to a shared network. The two-network Compose examples require **Docker Compose 2.33.1+** for [`gw_priority`](https://docs.docker.com/reference/compose-file/services/#gw_priority): a higher value on `default` selects it as the uplink and leaves the shared network for the guest bridge. For WebFig alone, see the single-network example below.

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
      - "127.0.0.1:8080:80"
      - "2222:22"
      - "2223:23"
      - "8728:8728"
      - "8729:8729"
    volumes:
      - ./routeros_data:/data
    networks:
      default:
        gw_priority: 1
      routeros_net: {}

networks:
  routeros_net:
    driver: bridge
```

With two networks the container gets `eth0` and `eth1`. The entrypoint preserves the interface carrying the IPv4 default route for published ports and bridges the other interface to the VM. Docker determines interface numbering and the default-route network, so do not assume that eth0 is the uplink. After RouterOS boots, open `http://127.0.0.1:8080` or connect via SSH (port 2222) or telnet (port 2223).

### WebFig on a single network or VPS

Publish **container port 80** to use WebFig. `EXPOSE` in the Dockerfile does not publish a port on the host. This minimal Compose example uses the default network only:

```yml
services:
  routeros:
    image: evilfreelancer/docker-routeros:latest
    restart: unless-stopped
    devices:
      - /dev/kvm  # omit if unavailable; QEMU will use slower emulation
    ports:
      - "127.0.0.1:8080:80"
```

Run `docker compose up -d`, wait for RouterOS to boot, and open `http://127.0.0.1:8080` on the Docker host. For a remote VPS, keep the loopback binding and run an SSH tunnel from your workstation:

```bash
ssh -N -L 8080:127.0.0.1:8080 user@vps
```

Then open `http://127.0.0.1:8080` on your workstation. Replace `user@vps` with your VPS SSH login. Avoid publishing an unauthenticated RouterOS management interface to the internet; set a strong RouterOS password and restrict access. Other port mappings without a host IP bind on all host interfaces.

If WebFig does not open, check `docker compose logs --tail=100 routeros`. DHCP `OFFER` and `ACK` messages are normal guest address negotiation, not KVM errors. A running container does not mean RouterOS has finished booting. For a customized guest, check `/ip service print` and its firewall rules to confirm that the `www` service allows access. HTTPS on port 443 requires a configured `www-ssl` service and certificate inside RouterOS.

Older images moved eth0 into the guest bridge when only one network was attached, which could break published ports even after RouterOS booted. Their two-network mode also assumed eth0 was always the uplink. Rebuild with the fixed entrypoint; attaching another network alone is not a reliable workaround for an older image.

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

- **Two networks (recommended for direct guest networking):** Attach the container to an uplink network and a shared network. The entrypoint preserves the interface carrying the IPv4 default route for QEMU hostfwd, and bridges the other interface with the VM TAP. This works whether Docker assigns the uplink to eth0 or eth1. The guest gets an address on the bridged network via DHCP. Ensure that the intended shared network is the non-uplink network. Two-network mode requires an IPv4 default route on eth0 or eth1; if the entrypoint cannot identify it, it stops before changing either interface.

- **Single network:** The container keeps eth0 and its Docker-managed address. QEMU user-mode networking forwards the supported management ports into the guest, including HTTP (80) and HTTPS (443). No TAP bridge or container-side DHCP server is started. Other containers can reach forwarded services through the container address, but the guest does not have a direct layer-2 presence on the Docker network. Publishing additional ports alone does not add QEMU forwards; use the two-network TAP mode for direct guest networking.

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
    networks:
      default:
        gw_priority: 1
      routeros_net: {}

  routeros2:
    image: evilfreelancer/docker-routeros:latest
    restart: unless-stopped
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun", "/dev/kvm"]
    ports: ["3222:22", "3223:23", "18728:8728", "18729:8729"]
    volumes: ["./routeros_data2:/data"]
    networks:
      default:
        gw_priority: 1
      routeros_net: {}
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
    networks:
      default:
        gw_priority: 1
      network1: {}

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
| `ROUTEROS_NIC_MAC` | (generated) | MAC of the guest TAP NIC in two-network mode. At start the value is read from `ROUTEROS_DATA_DIR/nic_mac` if the file exists; otherwise the env is used if set, else a unique MAC is generated and written to that file so it persists per volume. This does not configure the user-mode NIC in single-network mode. |
| `ROUTEROS_DHCP_DNS` | `8.8.8.8 8.8.4.4` | Space-separated DNS servers passed to the guest through the TAP bridge's DHCP server in two-network mode. Unused in single-network mode, which uses QEMU's default DNS settings. |
| `ROUTEROS_ETH_PROMISC` | `1` | Set to `1` to enable promiscuous mode on the non-uplink bridge port (eth0 or eth1 in two-network mode). Set to `0` to disable. Unused in single-network mode. |
| `ROUTEROS_DATA_DIR` | `/data` | Directory used for persistent data: a second disk image file is stored here and the bridge NIC MAC is saved in `nic_mac`. Mount a Docker volume here so the second disk and MAC persist. See "Second disk (volume)" below. |
| `ROUTEROS_DISK2_SIZE` | `256M` | Size of the second disk image when it is created automatically (e.g. `512M`, `1G`). Used only when `ROUTEROS_DATA_DIR/disk2.raw` does not exist yet. |

Two-network TAP example with custom DNS and MAC (attach two networks as shown above):

```yml
  routeros:
    image: evilfreelancer/docker-routeros:latest
    environment:
      ROUTEROS_NIC_MAC: "54:05:AB:CD:12:31"
      ROUTEROS_DHCP_DNS: "1.1.1.1 1.0.0.1"
      ROUTEROS_ETH_PROMISC: "1"
```

## Second disk (volume)

When you mount a volume at `ROUTEROS_DATA_DIR` (default `/data`), the entrypoint creates a raw disk image file `disk2.raw` there if it does not exist (size from `ROUTEROS_DISK2_SIZE`, default 256M). This file is attached to the VM as a second IDE disk (hdb). RouterOS sees it as a block device (e.g. `sata1` in `/disk print`).

**One-time setup in RouterOS:** format the second disk so it appears in `/file`:

```
/disk format sata1 file-system=ext4 label=data
```

After formatting, the disk is mounted automatically and appears in `/file print` (e.g. as `sata1`). You can use it for backups, scripts, logs, proxy cache, or any persistent data. The data is stored in `disk2.raw` on the host, so it survives container restarts and image updates.

The same directory holds `nic_mac` for the bridge NIC; each volume keeps its own MAC and its own second disk.

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
    environment:
      ROUTEROS_DISK2_SIZE: "512M"   # optional; default 256M
    networks:
      default:
        gw_priority: 1
      routeros_net: {}
```

Here `./routeros_data` is mounted at `/data`. On first start, `routeros_data/disk2.raw` is created (512M in this example). In RouterOS, run `/disk format sata1 file-system=ext4 label=data` once; then the second disk is available in `/file` and persists across restarts.

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

## Tests

Run the entrypoint regression tests with Python 3 and Bash; they do not require Docker or third-party Python packages:

```bash
python3 -m unittest discover -s tests -v
bash -n scripts/entrypoint.sh
```

To test WebFig against fresh RouterOS guests with one and two Docker networks, build the image and enable the Docker smoke tests:

```bash
docker build --build-arg ROUTEROS_VERSION=7.21.4 -t routeros-webfig-test .
ROUTEROS_TEST_IMAGE=routeros-webfig-test python3 -m unittest discover -s tests -v
```

The smoke tests require a local Linux Docker daemon and `/dev/net/tun` for the two-network case. They use KVM on x86_64 when `/dev/kvm` exists, publish HTTP on random loopback ports, and remove their temporary containers and networks on completion. Each guest has a 300-second boot budget; set `ROUTEROS_TEST_TIMEOUT` to a positive number of seconds to adjust it for slower emulation. Without `ROUTEROS_TEST_IMAGE`, these two tests are skipped.

## Links

* [MikroTik RouterOS in Docker using QEMU](https://habr.com/ru/articles/498012/) (Habr) - Setup guide for RouterOS in Docker with QEMU.
* [RouterOS API Client](https://github.com/EvilFreelancer/routeros-api-php) - PHP library for the RouterOS API.
* [VR Network Lab](https://github.com/vrnetlab/vrnetlab) - Run network equipment in Docker; alternative for production-like RouterOS.
* [qemu-docker](https://github.com/joshkunz/qemu-docker) - QEMU in Docker.
* [QEMU/KVM on Docker](https://github.com/ennweb/docker-kvm) - QEMU/KVM virtualization in Docker.
* [tenable/routeros](https://github.com/tenable/routeros) - RouterOS security research tooling and proof of concepts (Winbox, JSProxy, scanners, honeypots).
* https://help.mikrotik.com/docs/spaces/ROS/pages/91193346/Disks
