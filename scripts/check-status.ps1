# ================================================================
#  check-status.ps1  –  Kiểm tra nhanh trạng thái MongoDB Cluster
#
#  Đề tài 21 | Nguyễn Minh Khôi | MSSV: 49.01.104.073
#  Cách chạy: .\scripts\check-status.ps1
# ================================================================

function Get-ContainerState([string]$Name) {
    return docker inspect $Name --format "{{.State.Status}}" 2>&1
}

Write-Host ""
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  MongoDB Replica Set (rs0)  –  Cluster Health Check" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# ── Container status ──────────────────────────────────────────────
Write-Host ""
Write-Host "  [ Docker Containers ]" -ForegroundColor Yellow
$ports = @{ "mongo1"=27017; "mongo2"=27018; "mongo3"=27019 }
foreach ($node in @("mongo1","mongo2","mongo3")) {
    $st  = Get-ContainerState $node
    $col = if ($st -eq "running") { "Green" } else { "Red" }
    $sym = if ($st -eq "running") { "●" }      else { "○" }
    Write-Host ("  {0} {1,-8}  port:{2}  [{3}]" -f $sym, $node, $ports[$node], $st) -ForegroundColor $col
}

# ── Replica Set status ────────────────────────────────────────────
Write-Host ""
Write-Host "  [ Replica Set Members ]" -ForegroundColor Yellow

$gotStatus = $false
foreach ($node in @("mongo1","mongo2","mongo3")) {
    if ((Get-ContainerState $node) -ne "running") { continue }

    $raw = docker exec $node mongosh `
        -u admin -p AdminPass123 `
        --authenticationDatabase admin `
        --quiet --eval `
        "rs.status().members.forEach(m=>print(m.name+'|'+m.stateStr+'|'+m.health+'|'+m.optime.ts))" 2>&1

    if ($raw -and $raw -notmatch "Error|MongoServerError|connect ECONNREFUSED") {
        Write-Host "  (truy vấn từ: $node)" -ForegroundColor DarkGray
        $raw | ForEach-Object {
            $parts = $_ -split '\|'
            if ($parts.Count -ge 3) {
                $name  = $parts[0]; $state = $parts[1]; $health = $parts[2]
                $icon  = switch ($state) {
                    "PRIMARY"   { "👑" } "SECONDARY" { "🔄" } default { "❓" }
                }
                $col   = switch ($state) {
                    "PRIMARY"   { "Green" } "SECONDARY" { "Cyan" } default { "Red" }
                }
                $healthStr = if ($health -eq "1") { "healthy" } else { "UNHEALTHY" }
                Write-Host ("  {0} {1,-22} {2,-14} [{3}]" -f $icon, $name, $state, $healthStr) -ForegroundColor $col
            }
        }
        $gotStatus = $true
        break
    }
}

if (-not $gotStatus) {
    Write-Host "  ❌ Không thể kết nối với bất kỳ node nào!" -ForegroundColor Red
    Write-Host "     → Chạy: docker compose up -d" -ForegroundColor Yellow
    Write-Host "     → Hoặc: .\scripts\setup.ps1" -ForegroundColor Yellow
}

# ── Connection string ─────────────────────────────────────────────
Write-Host ""
Write-Host "  [ Kết nối ]" -ForegroundColor Yellow
Write-Host "  mongosh: " -NoNewline -ForegroundColor Gray
Write-Host "mongodb://admin:AdminPass123@localhost:27017,localhost:27018,localhost:27019/admin?replicaSet=rs0" -ForegroundColor Cyan
Write-Host ""
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
