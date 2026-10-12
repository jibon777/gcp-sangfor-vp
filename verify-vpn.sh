#!/usr/bin/env bash
# ==============================================================================
# SCRIPT VERIFIKASI STATUS VPN TUNNEL & GATEWAY (GCP)
# ==============================================================================
set -euo pipefail

PROJECT_ID="dev-aji"
REGION="asia-southeast2"
TUNNEL_NAME="tunnel-to-sangfor"
VPN_GW_NAME="vpn-gw-sangfor-lab"
GCP_VPN_IP_NAME="gcp-vpn-ip-lab"

echo "=========================================================="
echo " Project: ${PROJECT_ID} | Region: ${REGION} (Jakarta)"
echo " [1/4] Status IP Publik Statis GCP"
echo "=========================================================="
gcloud compute addresses describe "${GCP_VPN_IP_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --format="table(name, address, status)" || true

echo ""
echo "=========================================================="
echo " [2/4] Status Forwarding Rules"
echo "=========================================================="
gcloud compute forwarding-rules list --project="${PROJECT_ID}" --filter="region:(${REGION}) AND target:(vpn-gw-sangfor-lab)" --format="table(name, IPAddress, IPProtocol, target)" || true

echo ""
echo "=========================================================="
echo " [3/4] Status VPN Tunnel (IKE Phase 1 & 2)"
echo "=========================================================="
gcloud compute vpn-tunnels describe "${TUNNEL_NAME}" --region="${REGION}" --project="${PROJECT_ID}" \
    --format="table(name, status, detailedStatus, peerIp, ikeVersion, localTrafficSelector, remoteTrafficSelector)" || true

echo ""
echo "=========================================================="
echo " [4/4] Status Routing & Firewall"
echo "=========================================================="
echo "--- Static Route ---"
gcloud compute routes list --project="${PROJECT_ID}" --filter="name:route-to-sangfor-lab" --format="table(name, destRange, nextHopVpnTunnel, priority)" || true

echo ""
echo "--- Firewall Rule ---"
gcloud compute firewall-rules list --project="${PROJECT_ID}" --filter="name:allow-vpn-from-sangfor" --format="table(name, direction, sourceRanges.list():label=SRC_RANGES, allowed[].map().firewall_rule().list():label=ALLOWED)" || true

echo ""
echo "=========================================================="
echo " Interpretasi Status Tunnel:"
echo " - 'ESTABLISHED'          : VPN aktif & siap dilewati traffic."
echo " - 'First handshake'      : GCP sedang menunggu respon IKE Phase 1 dari Sangfor."
echo " - 'Waiting for peer'     : Sangfor belum menginisiasi koneksi atau IP/port belum sampai."
echo " - 'Negotiation failed'   : Cek kesesuaian PSK, IKE version, atau Traffic Selector!"
echo "=========================================================="
