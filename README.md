# Lab: Site-to-Site IPsec VPN (GCP Classic VPN to Sangfor Firewall)

Panduan deployment dan konfigurasi Site-to-Site IPsec VPN Policy-Based antara **Google Cloud Platform (GCP)** pada project **`dev-aji`** region **`asia-southeast2` (Jakarta)** dan **Sangfor Next-Generation Firewall (NGAF)**.

> [!NOTE]
> Konfigurasi ini telah disesuaikan karena **user/remote network di sisi Sangfor menggunakan IP Publik** (bukan private IP RFC 1918). Lalu lintas menuju IP publik target akan di-routing secara spesifik melalui VPN tunnel tanpa mengganggu koneksi internet reguler lainnya.

---

## 1. Arsitektur & Topologi Jaringan

```mermaid
flowchart LR
    subgraph GCP["Google Cloud Platform (dev-aji | asia-southeast2 - Jakarta)"]
        direction TB
        VM["GCP Instances<br/>Subnet: 10.184.0.0/20"]
        VPC["VPC Network: default"]
        GW["Target VPN Gateway<br/>vpn-gw-sangfor-lab"]
        IP_GCP["Static External IP<br/>(gcp-vpn-ip-lab)"]
        VM --> VPC --> GW --- IP_GCP
    end

    subgraph Internet["Public Internet / IPsec Tunnel"]
        Tunnel["IPsec Tunnel (IKEv2)<br/>ESP / UDP 500 / UDP 4500<br/>Policy-Based Selector"]
    end

    subgraph OnPrem["Sangfor Customer / On-Premise"]
        direction TB
        IP_SNG["Public IP WAN (Peer)<br/>103.111.211.56"]
        NGAF["Sangfor Firewall (NGAF)"]
        LAN["Target Host / Subnet Publik User<br/>103.111.211.56/32 (atau Blok Publik)"]
        IP_SNG --- NGAF --> LAN
    end

    IP_GCP <===> Tunnel <===> IP_SNG
```

---

## 2. Tabel Parameter Koneksi

| Parameter | Sisi GCP (Local) | Sisi Sangfor (Remote) | Catatan |
| :--- | :--- | :--- | :--- |
| **GCP Project ID** | `dev-aji` | - | Project aktif di Google Cloud |
| **Region** | `asia-southeast2` (Jakarta) | - | Lokasi resource VPN GCP |
| **VPC Network** | `default` | - | Jaringan VPC yang digunakan |
| **Public Endpoint IP** | Dinamis (Hasil Step 1) | `103.111.211.56` | IP Publik WAN Sangfor |
| **Local Subnet (CIDR)** | `10.184.0.0/20` | `103.111.211.56/32` | Subnet enkripsi lokal masing-masing sisi |
| **Remote Subnet (CIDR)** | `103.111.211.56/32` | `10.184.0.0/20` | Harus cermin simetris (*mirror*) |
| **IKE Version** | `IKEv2` | `IKEv2` | Wajib identik |
| **Pre-Shared Key (PSK)** | `vcw1nAT5S4+Fnv+JoziDLsU1kjs1/+MQ` | `vcw1nAT5S4+Fnv+JoziDLsU1kjs1/+MQ` | Wajib identik tanpa spasi |
| **Routing Method** | Policy-Based + Static Route | Policy-Based / Route-Based | Tanpa BGP |

> [!TIP]
> Jika user memiliki **alokasi blok subnet IP publik** (misalnya `103.111.211.0/24`), ganti nilai `103.111.211.56/32` dengan prefix subnet publik tersebut di kedua sisi (GCP & Sangfor).

---

## 3. Struktur Project

```text
gcp-sangfor-vpn/
├── README.md          # Dokumentasi teknis & panduan lengkap
├── setup-vpn.sh       # Script bash otomasi deployment (untuk Cloud Shell / Linux)
├── setup-vpn.ps1      # Script PowerShell otomasi deployment (untuk Windows)
├── verify-vpn.sh      # Script inspeksi status tunnel, gateway, route, dan firewall
└── cleanup-vpn.sh     # Script pembersihan (teardown) seluruh resource lab
```

---

## 4. Cara Menjalankan Konfigurasi di GCP

Pastikan project CLI aktif Anda adalah `dev-aji`:
```bash
gcloud config set project dev-aji
```

### Opsi A: Menggunakan Script Otomatis (Direkomendasikan)
Jalankan script bash di Google Cloud Shell / Linux:
```bash
chmod +x setup-vpn.sh verify-vpn.sh cleanup-vpn.sh
./setup-vpn.sh
```
Atau jika user memiliki range subnet publik tertentu:
```bash
REMOTE_TRAFFIC_SELECTOR="103.111.211.0/24" ./setup-vpn.sh
```

Atau jika menjalankan dari PowerShell lokal (Windows):
```powershell
.\setup-vpn.ps1
# Atau dengan parameter custom:
.\setup-vpn.ps1 -PeerIp "103.111.211.56" -RemoteTrafficSelector "103.111.211.56/32"
```

---

### Opsi B: Menjalankan Perintah gcloud Manual Step-by-Step

<details>
<summary><b>Klik untuk melihat langkah manual gcloud</b></summary>

#### Langkah 1: Pesan IP Publik Statis Regional
```bash
gcloud compute addresses create gcp-vpn-ip-lab \
    --project=dev-aji \
    --region=asia-southeast2 \
    --network-tier=PREMIUM
```
Cek IP Publik GCP yang didapat:
```bash
gcloud compute addresses describe gcp-vpn-ip-lab --project=dev-aji --region=asia-southeast2 --format="value(address)"
```

#### Langkah 2: Buat Target VPN Gateway
```bash
gcloud compute target-vpn-gateways create vpn-gw-sangfor-lab \
    --project=dev-aji \
    --network=default \
    --region=asia-southeast2
```

#### Langkah 3: Buat 3 Forwarding Rules
```bash
# Rule ESP (Payload IPsec)
gcloud compute forwarding-rules create fr-vpn-esp \
    --project=dev-aji \
    --region=asia-southeast2 \
    --ip-protocol=ESP \
    --address=gcp-vpn-ip-lab \
    --target-vpn-gateway=vpn-gw-sangfor-lab

# Rule UDP 500 (IKE)
gcloud compute forwarding-rules create fr-vpn-udp500 \
    --project=dev-aji \
    --region=asia-southeast2 \
    --ip-protocol=UDP \
    --ports=500 \
    --address=gcp-vpn-ip-lab \
    --target-vpn-gateway=vpn-gw-sangfor-lab

# Rule UDP 4500 (NAT-T)
gcloud compute forwarding-rules create fr-vpn-udp4500 \
    --project=dev-aji \
    --region=asia-southeast2 \
    --ip-protocol=UDP \
    --ports=4500 \
    --address=gcp-vpn-ip-lab \
    --target-vpn-gateway=vpn-gw-sangfor-lab
```

#### Langkah 4: Buat VPN Tunnel Policy-Based (IP Publik User)
```bash
# Catatan: Sesuaikan 103.111.211.56/32 jika user menggunakan subnet publik lain
gcloud compute vpn-tunnels create tunnel-to-sangfor \
    --project=dev-aji \
    --region=asia-southeast2 \
    --peer-address=103.111.211.56 \
    --shared-secret="vcw1nAT5S4+Fnv+JoziDLsU1kjs1/+MQ" \
    --ike-version=2 \
    --local-traffic-selector=10.184.0.0/20 \
    --remote-traffic-selector=103.111.211.56/32 \
    --target-vpn-gateway=vpn-gw-sangfor-lab
```

#### Langkah 5: Buat Rute Statis ke IP Publik User
```bash
gcloud compute routes create route-to-sangfor-lab \
    --project=dev-aji \
    --network=default \
    --next-hop-vpn-tunnel=tunnel-to-sangfor \
    --next-hop-vpn-tunnel-region=asia-southeast2 \
    --destination-range=103.111.211.56/32
```

#### Langkah 6: Buka Firewall GCP Ingress
```bash
gcloud compute firewall-rules create allow-vpn-from-sangfor \
    --project=dev-aji \
    --network=default \
    --direction=INGRESS \
    --action=ALLOW \
    --source-ranges=103.111.211.56/32 \
    --rules=tcp,udp,icmp
```
</details>

---

## 5. Panduan Konfigurasi di Sisi Sangfor Firewall (NGAF)

Saat mengatur IPsec VPN di Web Console Sangfor NGAF:

1. **Basic Settings / Peer Info:**
   - **Tunnel Name**: `GCP-VPN-Lab`
   - **Remote Peer IP**: Masukkan IP Publik GCP hasil Step 1.
   - **Authentication**: Pre-Shared Key (`vcw1nAT5S4+Fnv+JoziDLsU1kjs1/+MQ`).
   - **IKE Version**: `IKEv2`.

2. **Traffic Selectors / Encrypted Subnets:**
   - **Local Subnet**: `103.111.211.56/32` *(IP publik user / host target di Sangfor)*
   - **Remote Subnet**: `10.184.0.0/20` *(jaringan VPC GCP `dev-aji` Jakarta)*

3. **Phase 1 Proposal (IKE SA):**
   - **Encryption Algorithm**: `AES-256` atau `AES-128`
   - **Authentication / Hash**: `SHA-256`
   - **DH Group**: `Group 14 (2048-bit)` atau `Group 2`
   - **SA Lifetime**: `36000` detik (10 jam)

4. **Phase 2 Proposal (IPsec SA):**
   - **Encapsulation**: `ESP`
   - **Encryption Algorithm**: `AES-256` atau `AES-128`
   - **Authentication / Hash**: `SHA-256`
   - **PFS (Perfect Forward Secrecy)**: `Group 14` (atau *Disabled* jika disesuaikan)
   - **SA Lifetime**: `10800` detik (3 jam)

5. **Wajib: NAT Exemption / No-NAT Policy di Sangfor:**
   - Karena traffic menggunakan IP Publik di sisi lokal Sangfor, pastikan membuat rule **No-NAT (Bypass NAT)** untuk paket yang berasal dari IP Publik user menuju subnet GCP `10.184.0.0/20`.
   - Hal ini mencegah Sangfor melakukan Source NAT (SNAT) otomatis yang dapat merusak pencocokan IPsec Security Association (SA).

6. **Sangfor Security Policy:**
   - Pastikan terdapat firewall policy yang mengizinkan traffic dua arah antara subnet lokal user dan subnet GCP.

---

## 6. Catatan Khusus: Routing IP Publik via VPN di GCP

Mengapa rute IP publik di VPN GCP aman dan bagaimana cara kerjanya?

1. **Mekanisme Longest Prefix Match (LPM):**
   - Di tabel routing GCP VPC, aturan default internet adalah `0.0.0.0/0`.
   - Ketika dibuat static route ke `103.111.211.56/32` (atau prefix subnet spesifik) dengan next-hop VPN tunnel, rute ini memiliki prefix yang jauh lebih spesifik daripada `0.0.0.0/0`.
   - Oleh karena itu, hanya paket menuju IP publik user tersebut yang dibelokkan ke dalam VPN tunnel. Akses internet global lainnya tetap normal melalui Default Internet Gateway GCP.

2. **Format Host (/32) vs Subnet Blok:**
   - **Single Host (`/32`)**: Dipakai jika user hanya mengakses 1 mesin/server target di balik Sangfor, atau jika target yang diakses adalah alamat IP publik peer itu sendiri.
   - **Subnet Blok (`/24`, `/28`, dll.)**: Dipakai jika user memiliki alokasi subnet publik tersendiri untuk beberapa server.

---

## 7. Verifikasi & Troubleshooting

Jalankan script verifikasi:
```bash
./verify-vpn.sh
```

### Arti Status Tunnel di GCP Console:
- **`ESTABLISHED`**: Tunnel terhubung sempurna, IKE Phase 1 & Phase 2 sukses.
- **`First handshake`**: GCP sedang menunggu paket inisiasi/respon dari Sangfor. Cek apakah IP Publik GCP sudah dimasukkan di Sangfor dan port UDP 500/4500 tidak terblokir ISP.
- **`Waiting for peer`**: Sangfor belum memicu koneksi (GCP bersifat pasif menunggu traffic).
- **`Negotiation failed` / `TS_UNACCEPTABLE`**: Traffic Selector tidak cocok (ada perbedaan subnet antara local dan remote) atau PSK salah.

---

## 8. Cara Mengubah Remote Subnet / IP Publik

> **PENTING:** Parameter `--remote-traffic-selector` pada tunnel GCP bersifat permanen (*immutable*). Jika IP publik target perlu diubah:

1. Hapus rute lama:
   ```bash
   gcloud compute routes delete route-to-sangfor-lab --project=dev-aji --quiet
   ```
2. Hapus firewall rule lama (opsional jika subnet berubah):
   ```bash
   gcloud compute firewall-rules delete allow-vpn-from-sangfor --project=dev-aji --quiet
   ```
3. Hapus tunnel lama:
   ```bash
   gcloud compute vpn-tunnels delete tunnel-to-sangfor --region=asia-southeast2 --project=dev-aji --quiet
   ```
4. Buat ulang dengan IP/subnet baru menggunakan script `setup-vpn.sh` atau `setup-vpn.ps1`.
