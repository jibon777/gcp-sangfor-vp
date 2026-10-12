#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DEPLOYMENT POLICY-BASED CLASSIC VPN (GCP ke SANGFOR FIREWALL)
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# 1. PARAMETER & VARIABEL KONFIGURASI
# ------------------------------------------------------------------------------
# Project GCP
PROJECT_ID="dev-aji"

# Region & Jaringan GCP
REGION="asia-southeast2"
NETWORK="default"
GCP_VPN_IP_NAME="gcp-vpn-ip-lab"
VPN_GW_NAME="vpn-gw-sangfor-lab"
TUNNEL_NAME="tunnel-to-sangfor"
ROUTE_NAME="route-to-sangfor-lab"
FIREWALL_NAME="allow-vpn-from-sangfor"

# Subnet Lokal GCP (Traffic Selector Sisi GCP)
# Subnet asia-southeast2 (Jakarta) pada VPC default project dev-aji: 10.184.0.0/20.
LOCAL_TRAFFIC_SELECTOR="10.184.0.0/20"

# Parameter Sisi Remote (Sangfor Firewall)
PEER_IP="103.196.44.66"
REMOTE_TRAFFIC_SELECTOR="192.168.10.0/24" # Dummy IP subnet Sangfor (sesuaikan jika ada info baru)
SHARED_SECRET='vcw1nAT5S4+Fnv+JoziDLsU1kjs1/+MQ'
IKE_VERSION=2

echo "=========================================================="
echo "Memulai Deployment GCP Classic VPN ke Sangfor"
echo "Project ID          : ${PROJECT_ID}"
echo "Region              : ${REGION} (Jakarta)"
echo "VPC Network         : ${NETWORK}"
echo "Local Subnet (GCP)  : ${LOCAL_TRAFFIC_SELECTOR}"
echo "Peer Public IP      : ${PEER_IP}"
echo "Remote Subnet (Peer): ${REMOTE_TRAFFIC_SELECTOR}"
echo "=========================================================="

# ------------------------------------------------------------------------------
# 2. PESAN (RESERVE) IP PUBLIK STATIS REGIONAL DI GCP
# ------------------------------------------------------------------------------
echo "[Langkah 1/6] Memeriksa / Membuat Static External IP Address..."
if ! gcloud compute addresses describe "${GCP_VPN_IP_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud compute addresses create "${GCP_VPN_IP_NAME}" \
        --project="${PROJECT_ID}" \
        --region="${REGION}" \
        --network-tier=PREMIUM
    echo "-> IP statis ${GCP_VPN_IP_NAME} berhasil dipesan."
else
    echo "-> IP statis ${GCP_VPN_IP_NAME} sudah ada, melewati pembuatan."
fi

GCP_VPN_PUBLIC_IP=$(gcloud compute addresses describe "${GCP_VPN_IP_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --format="value(address)")
echo "-> IP Publik VPN Gateway GCP: ${GCP_VPN_PUBLIC_IP}"

# ------------------------------------------------------------------------------
# 3. BUAT TARGET VPN GATEWAY (CLASSIC VPN)
# ------------------------------------------------------------------------------
echo "[Langkah 2/6] Memeriksa / Membuat Target VPN Gateway..."
if ! gcloud compute target-vpn-gateways describe "${VPN_GW_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud compute target-vpn-gateways create "${VPN_GW_NAME}" \
        --project="${PROJECT_ID}" \
        --network="${NETWORK}" \
        --region="${REGION}"
    echo "-> Target VPN Gateway ${VPN_GW_NAME} berhasil dibuat."
else
    echo "-> Target VPN Gateway ${VPN_GW_NAME} sudah ada, melewati pembuatan."
fi

# ------------------------------------------------------------------------------
# 4. BUAT 3 FORWARDING RULES (ESP, UDP 500, UDP 4500)
# ------------------------------------------------------------------------------
echo "[Langkah 3/6] Memeriksa / Membuat Forwarding Rules..."

# Rule 1: ESP (IP Protocol 50)
if ! gcloud compute forwarding-rules describe fr-vpn-esp --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud compute forwarding-rules create fr-vpn-esp \
        --project="${PROJECT_ID}" \
        --region="${REGION}" \
        --ip-protocol=ESP \
        --address="${GCP_VPN_IP_NAME}" \
        --target-vpn-gateway="${VPN_GW_NAME}"
    echo "-> Forwarding rule fr-vpn-esp (ESP) berhasil dibuat."
fi

# Rule 2: UDP 500 (IKE)
if ! gcloud compute forwarding-rules describe fr-vpn-udp500 --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud compute forwarding-rules create fr-vpn-udp500 \
        --project="${PROJECT_ID}" \
        --region="${REGION}" \
        --ip-protocol=UDP \
        --ports=500 \
        --address="${GCP_VPN_IP_NAME}" \
        --target-vpn-gateway="${VPN_GW_NAME}"
    echo "-> Forwarding rule fr-vpn-udp500 (UDP:500) berhasil dibuat."
fi

# Rule 3: UDP 4500 (NAT-T)
if ! gcloud compute forwarding-rules describe fr-vpn-udp4500 --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud compute forwarding-rules create fr-vpn-udp4500 \
        --project="${PROJECT_ID}" \
        --region="${REGION}" \
        --ip-protocol=UDP \
        --ports=4500 \
        --address="${GCP_VPN_IP_NAME}" \
        --target-vpn-gateway="${VPN_GW_NAME}"
    echo "-> Forwarding rule fr-vpn-udp4500 (UDP:4500) berhasil dibuat."
fi

# ------------------------------------------------------------------------------
# 5. BUAT VPN TUNNEL (POLICY-BASED)
# ------------------------------------------------------------------------------
echo "[Langkah 4/6] Memeriksa / Membuat VPN Tunnel Policy-Based..."
if ! gcloud compute vpn-tunnels describe "${TUNNEL_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud compute vpn-tunnels create "${TUNNEL_NAME}" \
        --project="${PROJECT_ID}" \
        --region="${REGION}" \
        --peer-address="${PEER_IP}" \
        --shared-secret="${SHARED_SECRET}" \
        --ike-version="${IKE_VERSION}" \
        --local-traffic-selector="${LOCAL_TRAFFIC_SELECTOR}" \
        --remote-traffic-selector="${REMOTE_TRAFFIC_SELECTOR}" \
        --target-vpn-gateway="${VPN_GW_NAME}"
    echo "-> VPN Tunnel ${TUNNEL_NAME} berhasil dibuat."
else
    echo "-> VPN Tunnel ${TUNNEL_NAME} sudah ada, melewati pembuatan."
fi

# ------------------------------------------------------------------------------
# 6. BUAT STATIC ROUTE DI GCP VPC
# ------------------------------------------------------------------------------
echo "[Langkah 5/6] Memeriksa / Membuat Static Route..."
if ! gcloud compute routes describe "${ROUTE_NAME}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud compute routes create "${ROUTE_NAME}" \
        --project="${PROJECT_ID}" \
        --network="${NETWORK}" \
        --next-hop-vpn-tunnel="${TUNNEL_NAME}" \
        --next-hop-vpn-tunnel-region="${REGION}" \
        --destination-range="${REMOTE_TRAFFIC_SELECTOR}"
    echo "-> Route ${ROUTE_NAME} berhasil dibuat."
else
    echo "-> Route ${ROUTE_NAME} sudah ada, melewati pembuatan."
fi

# ------------------------------------------------------------------------------
# 7. BUAT INGRESS FIREWALL RULE
# ------------------------------------------------------------------------------
echo "[Langkah 6/6] Memeriksa / Membuat Firewall Rule Ingress..."
if ! gcloud compute firewall-rules describe "${FIREWALL_NAME}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud compute firewall-rules create "${FIREWALL_NAME}" \
        --project="${PROJECT_ID}" \
        --network="${NETWORK}" \
        --direction=INGRESS \
        --action=ALLOW \
        --source-ranges="${REMOTE_TRAFFIC_SELECTOR}" \
        --rules=tcp,udp,icmp
    echo "-> Firewall rule ${FIREWALL_NAME} berhasil dibuat."
else
    echo "-> Firewall rule ${FIREWALL_NAME} sudah ada, melewati pembuatan."
fi

# ------------------------------------------------------------------------------
# RINGKASAN OUTPUT
# ------------------------------------------------------------------------------
echo "=========================================================="
echo " Konfigurasi GCP Selesai!"
echo "=========================================================="
echo "Project ID             : ${PROJECT_ID}"
echo "Region                 : ${REGION} (Jakarta)"
echo "IP Publik Gateway GCP  : ${GCP_VPN_PUBLIC_IP}"
echo "IP Publik Sangfor      : ${PEER_IP}"
echo "Subnet GCP (Local)     : ${LOCAL_TRAFFIC_SELECTOR}"
echo "Subnet Sangfor (Remote): ${REMOTE_TRAFFIC_SELECTOR}"
echo "PSK                    : ${SHARED_SECRET}"
echo ""
echo "LANGKAH SELANJUTNYA PADA SANGFOR FIREWALL:"
echo "1. Pasang IP Publik GCP (${GCP_VPN_PUBLIC_IP}) sebagai Remote Peer IP."
echo "2. Set Local Subnet Sangfor = ${REMOTE_TRAFFIC_SELECTOR}"
echo "3. Set Remote Subnet Sangfor = ${LOCAL_TRAFFIC_SELECTOR}"
echo "4. Pastikan IKE Version = 2 dan Pre-Shared Key sama persis."
echo "5. Untuk verifikasi status tunnel, jalankan: ./verify-vpn.sh"
echo "=========================================================="
