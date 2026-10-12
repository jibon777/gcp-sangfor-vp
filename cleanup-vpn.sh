#!/usr/bin/env bash
# ==============================================================================
# SCRIPT PEMBERSIHAN (TEARDOWN) RESOURCE LAB VPN DI GCP
# ==============================================================================
set -euo pipefail

PROJECT_ID="dev-aji"
REGION="asia-southeast2"
GCP_VPN_IP_NAME="gcp-vpn-ip-lab"
VPN_GW_NAME="vpn-gw-sangfor-lab"
TUNNEL_NAME="tunnel-to-sangfor"
ROUTE_NAME="route-to-sangfor-lab"
FIREWALL_NAME="allow-vpn-from-sangfor"

echo "=========================================================="
echo " PERINGATAN: SCRIPT INI AKAN MENGHAPUS SELURUH RESOURCE LAB VPN"
echo " Project: ${PROJECT_ID}"
echo " Region : ${REGION} (Jakarta)"
echo "=========================================================="
read -p "Apakah Anda yakin ingin menghapus seluruh resource lab? (y/N): " -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Operasi dibatalkan."
    exit 0
fi

echo "[1/6] Menghapus Static Route..."
gcloud compute routes delete "${ROUTE_NAME}" --project="${PROJECT_ID}" --quiet || true

echo "[2/6] Menghapus Firewall Rule..."
gcloud compute firewall-rules delete "${FIREWALL_NAME}" --project="${PROJECT_ID}" --quiet || true

echo "[3/6] Menghapus VPN Tunnel..."
gcloud compute vpn-tunnels delete "${TUNNEL_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --quiet || true

echo "[4/6] Menghapus Forwarding Rules..."
gcloud compute forwarding-rules delete fr-vpn-esp --region="${REGION}" --project="${PROJECT_ID}" --quiet || true
gcloud compute forwarding-rules delete fr-vpn-udp500 --region="${REGION}" --project="${PROJECT_ID}" --quiet || true
gcloud compute forwarding-rules delete fr-vpn-udp4500 --region="${REGION}" --project="${PROJECT_ID}" --quiet || true

echo "[5/6] Menghapus Target VPN Gateway..."
gcloud compute target-vpn-gateways delete "${VPN_GW_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --quiet || true

echo "[6/6] Melepaskan (Release) Static External IP Address..."
gcloud compute addresses delete "${GCP_VPN_IP_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --quiet || true

echo "=========================================================="
echo " Seluruh resource lab VPN di project ${PROJECT_ID} (${REGION}) berhasil dibersihkan!"
echo "=========================================================="
