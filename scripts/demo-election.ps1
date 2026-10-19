# ================================================================
#  demo-election.ps1 - Live Demo: MongoDB Replica Set Election
#
#  Cach chay: .\scripts\demo-election.ps1
# ================================================================

$MONGO_USER = "admin"
$MONGO_PASS = "AdminPass123"
$MONGO_DB   = "admin"

function Invoke-Mongo {
    param([string]$Container, [string]$Eval)
    $res = docker exec $Container mongosh -u $MONGO_USER -p $MONGO_PASS --authenticationDatabase $MONGO_DB --quiet --eval $Eval 2>&1
    return $res
}

function Get-ClusterMembers {
    foreach ($node in @("mongo1","mongo2","mongo3")) {
        $state = (docker inspect $node --format "{{.State.Status}}" 2>&1).Trim()
        if ($state -ne "running") { continue }
        $evalStr = "JSON.stringify(rs.status().members.map(m=>({n:m.name,s:m.stateStr,h:m.health})))"
        $raw = Invoke-Mongo $node $evalStr
        try {
            $parsed = $raw | ConvertFrom-Json
            if ($parsed) { return $parsed, $node }
        } catch { }
    }
    return $null, $null
}

function Find-PrimaryContainer {
    foreach ($node in @("mongo1","mongo2","mongo3")) {
        $state = (docker inspect $node --format "{{.State.Status}}" 2>&1).Trim()
        if ($state -ne "running") { continue }
        $r = Invoke-Mongo $node "db.hello().isWritablePrimary"
        if ($r -match "true") { return $node }
    }
    return $null
}

function Show-ClusterStatus ([string]$Title) {
    $members, $fromNode = Get-ClusterMembers
    Write-Host ""
    Write-Host ("  [=== " + $Title + " ===]") -ForegroundColor Yellow
    if ($members) {
        foreach ($m in $members) {
            $nameShort = $m.n.Split(":")[0].PadRight(8)
            $port      = $m.n.Split(":")[1]
            $badge     = switch ($m.s) {
                "PRIMARY"   { "[PRIMARY *]" }
                "SECONDARY" { "[SECONDARY]" }
                default     { "[$($m.s)]" }
            }
            $color = switch ($m.s) {
                "PRIMARY"   { "Green" }
                "SECONDARY" { "Cyan"  }
                default     { "Red"   }
            }
            $health = if ($m.h -eq 1) { "HEALTHY" } else { "DOWN" }
            Write-Host ("  * {0} :{1}  ->  {2,-14} [{3}]" -f $nameShort, $port, $badge, $health) -ForegroundColor $color
        }
    } else {
        Write-Host "  * Khong the lay trang thai cluster tu cac node!" -ForegroundColor Red
    }
    if ($fromNode) {
        Write-Host "    (Du lieu doc tu node: $fromNode)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ==================================================================
#  DEMO BAT DAU
# ==================================================================
Clear-Host

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "     LIVE DEMO: MongoDB Replica Set - Automatic Election      " -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan

# -- BUOC 1: Trang thai ban dau ------------------------------------
Write-Host ""
Write-Host "  >>> BUOC 1: Kiem tra trang thai ban dau cua Cluster <<<" -ForegroundColor Magenta
Show-ClusterStatus "Trang thai TRUOC KHI TAT PRIMARY"

$primaryNode = Find-PrimaryContainer
if (-not $primaryNode) {
    Write-Host "  [X] Khong tim thay Primary! Cluster chua san sang." -ForegroundColor Red
    Write-Host "      Vui long kiem tra lai containers hoac chay setup." -ForegroundColor Yellow
    exit 1
}
Write-Host "  -> Primary hien tai la: " -NoNewline -ForegroundColor White
Write-Host "[$primaryNode]" -ForegroundColor Green

# -- BUOC 2: Ghi du lieu vao Primary -------------------------------
Write-Host ""
Write-Host "  >>> BUOC 2: Ghi du lieu kiem chung vao Primary <<<" -ForegroundColor Magenta

$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$writeScript = "use demoDB; db.election_log.insertOne({ event:'BEFORE_ELECTION', primary:'$primaryNode', ts:'$ts', note:'Du lieu ghi truoc khi Primary bi tat' }); print('-> Ghi thanh cong 1 ban ghi vao node: ' + '$primaryNode');"
$out = Invoke-Mongo $primaryNode $writeScript
Write-Host "  $out" -ForegroundColor White
Write-Host "  [OK] Da ghi du lieu thanh cong vao Primary ($primaryNode)" -ForegroundColor Green

# -- PAUSE: Hoi dong xac nhan --------------------------------------
Write-Host ""
Write-Host "  +---------------------------------------------------------+" -ForegroundColor Red
Write-Host "  |  [!] Nhan [ENTER] de TAT PRIMARY NGAY BAY GIO           |" -ForegroundColor Red
Write-Host "  +---------------------------------------------------------+" -ForegroundColor Red
Read-Host | Out-Null

# -- BUOC 3: Tat Primary -------------------------------------------
Write-Host ""
Write-Host "  >>> BUOC 3: Tat Node Primary ($primaryNode) <<<" -ForegroundColor Red
Write-Host "  -> Dang stop container: $primaryNode..." -ForegroundColor Red
docker stop $primaryNode | Out-Null

Write-Host "  [!] Container [$primaryNode] DA BI DUNG!" -ForegroundColor Red
Write-Host "  -> Bat dau bam gio do thoi gian Election..." -ForegroundColor Yellow

$electionStart = Get-Date

# -- BUOC 4: Theo doi Election real-time ---------------------------
Write-Host ""
Write-Host "  >>> BUOC 4: Quan sat qua trinh Election (Real-time) <<<" -ForegroundColor Magenta
Write-Host "  (He thong can Quorum >= 2/3 nodes de bau Primary moi)" -ForegroundColor DarkGray
Write-Host ""

$queryNode = if ($primaryNode -eq "mongo1") { "mongo2" } elseif ($primaryNode -eq "mongo2") { "mongo3" } else { "mongo2" }

$newPrimary   = $null
$maxWaitMs    = 35000
$pollInterval = 600

do {
    $elapsed = [int]((Get-Date) - $electionStart).TotalMilliseconds
    $elapsedSec = [math]::Round($elapsed / 1000, 1)

    $raw = docker exec $queryNode mongosh -u $MONGO_USER -p $MONGO_PASS --authenticationDatabase $MONGO_DB --quiet --eval "JSON.stringify(rs.status().members.map(m=>({n:m.name,s:m.stateStr})))" 2>&1

    try {
        $members = $raw | ConvertFrom-Json
        if ($members) {
            $line = "  [{0,4}s] " -f $elapsedSec
            foreach ($m in $members) {
                $shortName = $m.n.Split(":")[0]
                $tag = switch ($m.s) {
                    "PRIMARY"    { "[PRIMARY *]" }
                    "SECONDARY"  { "[SECONDARY]" }
                    default      { "[$($m.s)]" }
                }
                $line += "${shortName}:${tag}   "
            }
            Write-Host $line -ForegroundColor Gray

            $elected = $members | Where-Object { $_.s -eq "PRIMARY" -and $_.n.Split(":")[0] -ne $primaryNode }
            if ($elected) {
                $newPrimary = $elected.n.Split(":")[0]
            }
        }
    } catch {
        Write-Host ("  [{0,4}s] Dang cho bau chon..." -f $elapsedSec) -ForegroundColor DarkYellow
    }

    if ($newPrimary) { break }
    Start-Sleep -Milliseconds $pollInterval
} while ($elapsed -lt $maxWaitMs)

$totalSec = [math]::Round(((Get-Date) - $electionStart).TotalSeconds, 2)

# -- Ket qua Election ----------------------------------------------
Write-Host ""
if ($newPrimary) {
    Write-Host "  +========================================================+" -ForegroundColor Green
    Write-Host "  |  ELECTION THANH CONG!                                  |" -ForegroundColor Green
    Write-Host ("  |  * Thoi gian bau chon : {0,-8} giay                  |" -f $totalSec) -ForegroundColor Green
    Write-Host ("  |  * Primary moi        : [{0,-8}]                      |" -f $newPrimary) -ForegroundColor Green
    Write-Host ("  |  * Node da tat        : [{0,-8}]                      |" -f $primaryNode) -ForegroundColor Green
    Write-Host "  +========================================================+" -ForegroundColor Green
} else {
    Write-Host "  [!] Het thoi gian cho ($totalSec giay). Kiem tra thu cong." -ForegroundColor Red
}

# -- BUOC 5: Trang thai sau Election -------------------------------
Write-Host ""
Write-Host "  >>> BUOC 5: Kiem tra trang thai sau khi co Primary moi <<<" -ForegroundColor Magenta
Show-ClusterStatus "Trang thai SAU KHI ELECTION"

# -- BUOC 6: Kiem tra toan ven du lieu -----------------------------
Write-Host "  >>> BUOC 6: Kiem tra tinh toan ven du lieu <<<" -ForegroundColor Magenta
if ($newPrimary) {
    $checkScript = "use demoDB; print('So ban ghi election_log: ' + db.election_log.countDocuments()); print('Noi dung ban ghi: ' + JSON.stringify(db.election_log.findOne()));"
    $checkRes = Invoke-Mongo $newPrimary $checkScript
    Write-Host "  $checkRes" -ForegroundColor White
    Write-Host ""
    Write-Host "  [OK] DU LIEU NGUYEN VEN! Khong bi mat bat ky ban ghi nao!" -ForegroundColor Green
}

# -- BUOC 7: Khoi dong lai node cu ---------------------------------
Write-Host ""
Write-Host "  >>> BUOC 7: Khoi dong lai node cu (Rejoin Cluster) <<<" -ForegroundColor Magenta
Write-Host ""
Write-Host "  [!] Nhan [ENTER] de START lai " -NoNewline -ForegroundColor Yellow
Write-Host "[$primaryNode]" -NoNewline -ForegroundColor Cyan
Write-Host " va quan sat node tu dong gia nhap..." -ForegroundColor Yellow
Read-Host | Out-Null

Write-Host ""
Write-Host "  -> Dang khoi dong lai container $primaryNode..." -ForegroundColor Green
docker start $primaryNode | Out-Null
Write-Host "  -> Cho 10 giay de $primaryNode dong bo lai oplog voi cluster..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

Write-Host ""
Show-ClusterStatus "Trang thai cuoi cung (Sau khi $primaryNode rejoin)"

Write-Host "  DEMO HOAN TAT                               " -ForegroundColor Cyan
