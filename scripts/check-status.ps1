# ================================================================
#  check-status.ps1 - Kiem tra nhanh trang thai MongoDB Cluster
#
#  Cach chay: .\scripts\check-status.ps1
# ================================================================

function Get-ContainerState([string]$Name) {
    return (docker inspect $Name --format "{{.State.Status}}" 2>&1).Trim()
}

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  MongoDB Replica Set (rs0) - Cluster Health Check" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan

# -- Container status ----------------------------------------------
Write-Host ""
Write-Host "  [ Docker Containers ]" -ForegroundColor Yellow
$ports = @{ "mongo1"=27017; "mongo2"=27018; "mongo3"=27019 }
foreach ($node in @("mongo1","mongo2","mongo3")) {
    $st  = Get-ContainerState $node
    $col = if ($st -eq "running") { "Green" } else { "Red" }
    $sym = if ($st -eq "running") { "[OK]" } else { "[DOWN]" }
    Write-Host ("  {0,-7} {1,-8} port:{2} [{3}]" -f $sym, $node, $ports[$node], $st) -ForegroundColor $col
}

# -- Replica Set status --------------------------------------------
Write-Host ""
Write-Host "  [ Replica Set Members ]" -ForegroundColor Yellow

$gotStatus = $false
foreach ($node in @("mongo1","mongo2","mongo3")) {
    if ((Get-ContainerState $node) -ne "running") { continue }

    $evalCmd = "rs.status().members.forEach(m => print(m.name + '|' + m.stateStr + '|' + m.health))"
    $raw = docker exec $node mongosh -u admin -p AdminPass123 --authenticationDatabase admin --quiet --eval $evalCmd 2>&1

    if ($raw -and ($raw -notmatch "Error|MongoServerError|ECONNREFUSED")) {
        Write-Host "  (Lay du lieu tu node: $node)" -ForegroundColor DarkGray
        foreach ($line in ($raw -split "`r?`n")) {
            $line = $line.Trim()
            if (-not $line -or $line -notmatch '\|') { continue }
            $parts = $line -split '\|'
            if ($parts.Count -ge 3) {
                $mName   = $parts[0]
                $mState  = $parts[1]
                $mHealth = $parts[2]
                $badge   = switch ($mState) {
                    "PRIMARY"   { "[PRIMARY *]" }
                    "SECONDARY" { "[SECONDARY]" }
                    default     { "[$mState]" }
                }
                $col = switch ($mState) {
                    "PRIMARY"   { "Green" }
                    "SECONDARY" { "Cyan" }
                    default     { "Red" }
                }
                $healthStr = if ($mHealth -eq "1") { "HEALTHY" } else { "UNHEALTHY" }
                Write-Host ("  {0,-20} {1,-14} [{2}]" -f $mName, $badge, $healthStr) -ForegroundColor $col
            }
        }
        $gotStatus = $true
        break
    }
}

if (-not $gotStatus) {
    Write-Host "  [X] Khong the ket noi voi bat ky node nao dang chay!" -ForegroundColor Red
    Write-Host "     -> Chay: docker compose up -d" -ForegroundColor Yellow
}

# -- Connection string ---------------------------------------------
Write-Host ""
Write-Host "  [ Ket noi mongosh ]" -ForegroundColor Yellow
Write-Host "  mongodb://admin:AdminPass123@localhost:27017,localhost:27018,localhost:27019/admin?replicaSet=rs0" -ForegroundColor Cyan
Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""
