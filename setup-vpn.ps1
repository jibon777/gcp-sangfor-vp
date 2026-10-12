# ==============================================================================
# SCRIPT DEPLOYMENT POLICY-BASED CLASSIC VPN (GCP ke SANGFOR FIREWALL) - POWERSHELL
# ==============================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

# ------------------------------------------------------------------------------
# 1. PARAMETER & VARIABEL KONFIGURASI
# ------------------------------------------------------------------------------
$ProjectId            = "dev-aji"
$Region               = "asia-southeast2"
$Network              = "default"
$GcpVpnIpName         = "gcp-vpn-ip-lab"
$VpnGwName            = "vpn-gw-sangfor-lab"
$TunnelName           = "tunnel-to-sangfor"
$RouteName            = "route-to-sangfor-lab"
$FirewallName         = "allow-vpn-from-sangfor"

# Subnet Lokal GCP (Traffic Selector Sisi GCP)
# Subnet asia-southeast2 (Jakarta) pada VPC default project dev-aji: 10.184.0.0/20.
$LocalTrafficSelector = "10.184.0.0/20"

# Parameter Sisi Remote (Sangfor Firewall)
$PeerIp               = "103.196.44.66"
$RemoteTrafficSelector= "192.168.10.0/24" # Dummy IP subnet Sangfor
$SharedSecret         = "vcw1nAT5S4+Fnv+JoziDLsU1kjs1/+MQ"
$IkeVersion           = 2

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Memulai Deployment GCP Classic VPN ke Sangfor (PowerShell)" -ForegroundColor Cyan
Write-Host "Project ID          : $ProjectId"
Write-Host "Region              : $Region (Jakarta)"
Write-Host "VPC Network         : $Network"
Write-Host "Local Subnet (GCP)  : $LocalTrafficSelector"
Write-Host "Peer Public IP      : $PeerIp"
Write-Host "Remote Subnet (Peer): $RemoteTrafficSelector"
Write-Host "==========================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 2. PESAN (RESERVE) IP PUBLIK STATIS REGIONAL DI GCP
# ------------------------------------------------------------------------------
Write-Host "`n[Langkah 1/6] Memeriksa / Membuat Static External IP Address..." -ForegroundColor Yellow
$null = gcloud compute addresses describe $GcpVpnIpName --project=$ProjectId --region=$Region *>$null
if ($LASTEXITCODE -ne 0) {
    gcloud compute addresses create $GcpVpnIpName `
        --project=$ProjectId `
        --region=$Region `
        --network-tier=PREMIUM
    Write-Host "-> IP statis $GcpVpnIpName berhasil dibuat." -ForegroundColor Green
} else {
    Write-Host "-> IP statis $GcpVpnIpName sudah ada." -ForegroundColor DarkGray
}

$GcpVpnPublicIp = (gcloud compute addresses describe $GcpVpnIpName --project=$ProjectId --region=$Region --format="value(address)" 2>$null).Trim()
Write-Host "-> IP Publik VPN Gateway GCP: $GcpVpnPublicIp" -ForegroundColor Green

# ------------------------------------------------------------------------------
# 3. BUAT TARGET VPN GATEWAY (CLASSIC VPN)
# ------------------------------------------------------------------------------
Write-Host "`n[Langkah 2/6] Memeriksa / Membuat Target VPN Gateway..." -ForegroundColor Yellow
$null = gcloud compute target-vpn-gateways describe $VpnGwName --region=$Region --project=$ProjectId *>$null
if ($LASTEXITCODE -ne 0) {
    gcloud compute target-vpn-gateways create $VpnGwName `
        --project=$ProjectId `
        --network=$Network `
        --region=$Region
    Write-Host "-> Target VPN Gateway $VpnGwName berhasil dibuat." -ForegroundColor Green
} else {
    Write-Host "-> Target VPN Gateway $VpnGwName sudah ada." -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# 4. BUAT 3 FORWARDING RULES (ESP, UDP 500, UDP 4500)
# ------------------------------------------------------------------------------
Write-Host "`n[Langkah 3/6] Memeriksa / Membuat Forwarding Rules..." -ForegroundColor Yellow

# Rule 1: ESP
$null = gcloud compute forwarding-rules describe fr-vpn-esp --region=$Region --project=$ProjectId *>$null
if ($LASTEXITCODE -ne 0) {
    gcloud compute forwarding-rules create fr-vpn-esp `
        --project=$ProjectId `
        --region=$Region `
        --ip-protocol=ESP `
        --address=$GcpVpnIpName `
        --target-vpn-gateway=$VpnGwName
    Write-Host "-> Forwarding rule fr-vpn-esp (ESP) berhasil dibuat." -ForegroundColor Green
} else {
    Write-Host "-> Forwarding rule fr-vpn-esp (ESP) sudah ada." -ForegroundColor DarkGray
}

# Rule 2: UDP 500
$null = gcloud compute forwarding-rules describe fr-vpn-udp500 --region=$Region --project=$ProjectId *>$null
if ($LASTEXITCODE -ne 0) {
    gcloud compute forwarding-rules create fr-vpn-udp500 `
        --project=$ProjectId `
        --region=$Region `
        --ip-protocol=UDP `
        --ports=500 `
        --address=$GcpVpnIpName `
        --target-vpn-gateway=$VpnGwName
    Write-Host "-> Forwarding rule fr-vpn-udp500 (UDP:500) berhasil dibuat." -ForegroundColor Green
} else {
    Write-Host "-> Forwarding rule fr-vpn-udp500 (UDP:500) sudah ada." -ForegroundColor DarkGray
}

# Rule 3: UDP 4500
$null = gcloud compute forwarding-rules describe fr-vpn-udp4500 --region=$Region --project=$ProjectId *>$null
if ($LASTEXITCODE -ne 0) {
    gcloud compute forwarding-rules create fr-vpn-udp4500 `
        --project=$ProjectId `
        --region=$Region `
        --ip-protocol=UDP `
        --ports=4500 `
        --address=$GcpVpnIpName `
        --target-vpn-gateway=$VpnGwName
    Write-Host "-> Forwarding rule fr-vpn-udp4500 (UDP:4500) berhasil dibuat." -ForegroundColor Green
} else {
    Write-Host "-> Forwarding rule fr-vpn-udp4500 (UDP:4500) sudah ada." -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# 5. BUAT VPN TUNNEL (POLICY-BASED)
# ------------------------------------------------------------------------------
Write-Host "`n[Langkah 4/6] Memeriksa / Membuat VPN Tunnel Policy-Based..." -ForegroundColor Yellow
$null = gcloud compute vpn-tunnels describe $TunnelName --region=$Region --project=$ProjectId *>$null
if ($LASTEXITCODE -ne 0) {
    gcloud compute vpn-tunnels create $TunnelName `
        --project=$ProjectId `
        --region=$Region `
        --peer-address=$PeerIp `
        --shared-secret="$SharedSecret" `
        --ike-version=$IkeVersion `
        --local-traffic-selector=$LocalTrafficSelector `
        --remote-traffic-selector=$RemoteTrafficSelector `
        --target-vpn-gateway=$VpnGwName
    Write-Host "-> VPN Tunnel $TunnelName berhasil dibuat." -ForegroundColor Green
} else {
    Write-Host "-> VPN Tunnel $TunnelName sudah ada." -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# 6. BUAT STATIC ROUTE DI GCP VPC
# ------------------------------------------------------------------------------
Write-Host "`n[Langkah 5/6] Memeriksa / Membuat Static Route..." -ForegroundColor Yellow
$null = gcloud compute routes describe $RouteName --project=$ProjectId *>$null
if ($LASTEXITCODE -ne 0) {
    gcloud compute routes create $RouteName `
        --project=$ProjectId `
        --network=$Network `
        --next-hop-vpn-tunnel=$TunnelName `
        --next-hop-vpn-tunnel-region=$Region `
        --destination-range=$RemoteTrafficSelector
    Write-Host "-> Route $RouteName berhasil dibuat." -ForegroundColor Green
} else {
    Write-Host "-> Route $RouteName sudah ada." -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# 7. BUAT INGRESS FIREWALL RULE
# ------------------------------------------------------------------------------
Write-Host "`n[Langkah 6/6] Memeriksa / Membuat Firewall Rule Ingress..." -ForegroundColor Yellow
$null = gcloud compute firewall-rules describe $FirewallName --project=$ProjectId *>$null
if ($LASTEXITCODE -ne 0) {
    gcloud compute firewall-rules create $FirewallName `
        --project=$ProjectId `
        --network=$Network `
        --direction=INGRESS `
        --action=ALLOW `
        --source-ranges=$RemoteTrafficSelector `
        '--rules=tcp,udp,icmp'
    Write-Host "-> Firewall rule $FirewallName berhasil dibuat." -ForegroundColor Green
} else {
    Write-Host "-> Firewall rule $FirewallName sudah ada." -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# RINGKASAN OUTPUT
# ------------------------------------------------------------------------------
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " Konfigurasi GCP Selesai!" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Project ID             : $ProjectId"
Write-Host "Region                 : $Region (Jakarta)"
Write-Host "IP Publik Gateway GCP  : $GcpVpnPublicIp"
Write-Host "IP Publik Sangfor      : $PeerIp"
Write-Host "Subnet GCP (Local)     : $LocalTrafficSelector"
Write-Host "Subnet Sangfor (Remote): $RemoteTrafficSelector"
Write-Host "PSK                    : $SharedSecret"
Write-Host ""
Write-Host "LANGKAH SELANJUTNYA PADA SANGFOR FIREWALL:" -ForegroundColor Yellow
Write-Host "1. Pasang IP Publik GCP ($GcpVpnPublicIp) sebagai Remote Peer IP."
Write-Host "2. Set Local Subnet Sangfor = $RemoteTrafficSelector"
Write-Host "3. Set Remote Subnet Sangfor = $LocalTrafficSelector"
Write-Host "4. Pastikan IKE Version = 2 dan Pre-Shared Key sama persis."
Write-Host "5. Untuk verifikasi status tunnel, jalankan: ./verify-vpn.sh"
Write-Host "==========================================================" -ForegroundColor Cyan
