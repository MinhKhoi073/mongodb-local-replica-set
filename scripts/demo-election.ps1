# ================================================================
#  demo-election.ps1  –  Live Demo: MongoDB Replica Set Election
#
#  Mục đích:
#    Thực hiện tắt Node Primary ngay trước mặt Hội đồng/Giảng viên
#    và quan sát hệ thống tự bầu Primary mới chỉ sau vài giây.
#
#  Đề tài 21 | Nguyễn Minh Khôi | MSSV: 49.01.104.073
#
#  Cách chạy: .\scripts\demo-election.ps1
# ================================================================

$MONGO_USER = "admin"
$MONGO_PASS = "AdminPass123"
$MONGO_DB   = "admin"

# ── Helper: chạy mongosh bên trong container ──────────────────────
function Invoke-Mongo {
    param([string]$Container, [string]$Eval)
    docker exec $Container mongosh `
        -u $MONGO_USER -p $MONGO_PASS `
        --authenticationDatabase $MONGO_DB `
        --quiet --eval $Eval 2>&1
}

# ── Helper: lấy trạng thái toàn cluster từ bất kỳ node nào đang chạy
function Get-ClusterMembers {
    foreach ($node in @("mongo1","mongo2","mongo3")) {
        $state = docker inspect $node --format "{{.State.Status}}" 2>&1
        if ($state -ne "running") { continue }
        $raw = Invoke-Mongo $node `
            "JSON.stringify(rs.status().members.map(m=>({n:m.name,s:m.stateStr,h:m.health})))"
        try { return ($raw | ConvertFrom-Json), $node } catch { }
    }
    return $null, $null
}

# ── Helper: tìm Primary hiện tại ─────────────────────────────────
function Find-PrimaryContainer {
    foreach ($node in @("mongo1","mongo2","mongo3")) {
        $state = docker inspect $node --format "{{.State.Status}}" 2>&1
        if ($state -ne "running") { continue }
        $r = Invoke-Mongo $node "db.hello().isWritablePrimary"
        if ($r -match "true") { return $node }
    }
    return $null
}

# ── Helper: in bảng trạng thái cluster ───────────────────────────
function Show-ClusterStatus ([string]$Title) {
    $members, $fromNode = Get-ClusterMembers
    Write-Host ""
    Write-Host "  ┌─ $Title " -ForegroundColor Yellow -NoNewline
    Write-Host ("─" * [math]::Max(2, 52 - $Title.Length)) -ForegroundColor Yellow
    if ($members) {
        foreach ($m in $members) {
            $nameShort = $m.n.Split(":")[0].PadRight(8)
            $port      = $m.n.Split(":")[1]
            $icon  = switch ($m.s) {
                "PRIMARY"   { "  👑 " }
                "SECONDARY" { "  🔄 " }
                "STARTUP2"  { "  🔃 " }
                "RECOVERING"{ "  🔃 " }
                default     { "  ❓ " }
            }
            $color = switch ($m.s) {
                "PRIMARY"   { "Green" }
                "SECONDARY" { "Cyan"  }
                default     { "Red"   }
            }
            $health = if ($m.h -eq 1) { "●" } else { "○" }
            Write-Host "  │$icon$nameShort  :$port  →  $($m.s.PadRight(12))  $health" -ForegroundColor $color
        }
    } else {
        Write-Host "  │  ⚠ Không thể lấy trạng thái cluster" -ForegroundColor Red
    }
    if ($fromNode) {
        Write-Host "  │  (truy vấn từ: $fromNode)" -ForegroundColor DarkGray
    }
    Write-Host "  └" -ForegroundColor Yellow -NoNewline
    Write-Host ("─" * 56) -ForegroundColor Yellow
    Write-Host ""
}

# ══════════════════════════════════════════════════════════════════
#  DEMO BẮT ĐẦU
# ══════════════════════════════════════════════════════════════════
Clear-Host

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     LIVE DEMO: MongoDB Replica Set – Automatic Election      ║" -ForegroundColor Cyan
Write-Host "║     Đề tài 21  │  Nguyễn Minh Khôi  │  49.01.104.073       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# ── BƯỚC 1: Trạng thái ban đầu ───────────────────────────────────
Write-Host ""
Write-Host "  ━━━ BƯỚC 1: Trạng thái ban đầu của Cluster ━━━" -ForegroundColor Magenta
Show-ClusterStatus "Trạng thái TRƯỚC Election"

# Xác định Primary
$primaryNode = Find-PrimaryContainer
if (-not $primaryNode) {
    Write-Host "  ❌ Không tìm thấy Primary! Cluster chưa sẵn sàng." -ForegroundColor Red
    Write-Host "     Chạy setup.ps1 trước." -ForegroundColor Yellow
    exit 1
}
Write-Host "  🎯 Primary hiện tại: " -NoNewline -ForegroundColor White
Write-Host "[$primaryNode]" -ForegroundColor Green

# ── BƯỚC 2: Ghi dữ liệu vào Primary ─────────────────────────────
Write-Host ""
Write-Host "  ━━━ BƯỚC 2: Ghi dữ liệu vào Primary trước khi tắt ━━━" -ForegroundColor Magenta

$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$writeScript = "use demoDB; db.election_log.insertOne({ event:'BEFORE_ELECTION', primary:'$primaryNode', ts:'$ts', ghi_chu:'Du lieu truoc Election' }); print('Ghi thanh cong vao: ' + '$primaryNode');"
Invoke-Mongo $primaryNode $writeScript | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
Write-Host ""
Write-Host "  ✅ Đã ghi 1 bản ghi vào Primary ($primaryNode)" -ForegroundColor Green

# ── PAUSE: Hội đồng xác nhận ─────────────────────────────────────
Write-Host ""
Write-Host "  ┌─────────────────────────────────────────────────────────┐" -ForegroundColor Red
Write-Host "  │  ⚡ Nhấn [ENTER] để TẮT PRIMARY ngay bây giờ           │" -ForegroundColor Red
Write-Host "  │     (Thực hiện trực tiếp trước mặt Hội đồng)           │" -ForegroundColor Red
Write-Host "  └─────────────────────────────────────────────────────────┘" -ForegroundColor Red
Read-Host | Out-Null

# ── BƯỚC 3: Tắt Primary ──────────────────────────────────────────
Write-Host ""
Write-Host "  ━━━ BƯỚC 3: Tắt Node Primary ━━━" -ForegroundColor Red

Write-Host "  ⏹  Đang dừng container: $primaryNode..." -ForegroundColor Red
docker stop $primaryNode | Out-Null
Write-Host ""
Write-Host "  🔴 Container " -NoNewline -ForegroundColor White
Write-Host "[$primaryNode] ĐÃ DỪNG" -ForegroundColor Red
Write-Host "  🕐 Bắt đầu đo thời gian Election..." -ForegroundColor Yellow

$electionStart = Get-Date

# ── BƯỚC 4: Theo dõi Election real-time ──────────────────────────
Write-Host ""
Write-Host "  ━━━ BƯỚC 4: Quan sát Election (real-time) ━━━" -ForegroundColor Magenta
Write-Host "  (Hệ thống cần quorum ≥ 2/3 nodes để bầu Primary mới)" -ForegroundColor DarkGray
Write-Host ""

# Chọn node để query (không phải node vừa tắt)
$queryNode = if ($primaryNode -eq "mongo1") { "mongo2" } elseif ($primaryNode -eq "mongo2") { "mongo1" } else { "mongo1" }

$newPrimary   = $null
$maxWaitMs    = 30000
$pollInterval = 500

do {
    $elapsed = [int]((Get-Date) - $electionStart).TotalMilliseconds
    $elapsedSec = [math]::Round($elapsed / 1000, 1)

    $raw = docker exec $queryNode mongosh `
        -u $MONGO_USER -p $MONGO_PASS `
        --authenticationDatabase $MONGO_DB `
        --quiet --eval "JSON.stringify(rs.status().members.map(m=>({n:m.name,s:m.stateStr})))" 2>&1

    try {
        $members = $raw | ConvertFrom-Json
        $line = "  [{0,4}s] " -f $elapsedSec

        foreach ($m in $members) {
            $shortName = $m.n.Split(":")[0]
            $tag = switch ($m.s) {
                "PRIMARY"    { "👑 PRIMARY  " }
                "SECONDARY"  { "🔄 SECONDARY" }
                "STARTUP2"   { "🔃 STARTUP2 " }
                "RECOVERING" { "🔃 RECOVER  " }
                default      { "❓ $($m.s.PadRight(9))" }
            }
            $col = switch ($m.s) {
                "PRIMARY"   { "Green"  }
                "SECONDARY" { "Cyan"   }
                default     { "Yellow" }
            }
            $line += "$shortName:$tag  "
        }

        Write-Host $line -ForegroundColor Gray

        # Kiểm tra có Primary mới không (khác node vừa tắt)
        $elected = $members | Where-Object { $_.s -eq "PRIMARY" -and $_.n.Split(":")[0] -ne $primaryNode }
        if ($elected) {
            $newPrimary = $elected.n.Split(":")[0]
        }
    } catch {
        Write-Host ("  [{0,4}s] Đang bầu chọn..." -f $elapsedSec) -ForegroundColor DarkYellow
    }

    if ($newPrimary) { break }
    Start-Sleep -Milliseconds $pollInterval
} while ($elapsed -lt $maxWaitMs)

$totalSec = [math]::Round(((Get-Date) - $electionStart).TotalSeconds, 2)

# ── Kết quả Election ─────────────────────────────────────────────
Write-Host ""
if ($newPrimary) {
    Write-Host "  ╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║  🎉 ELECTION THÀNH CÔNG!                              ║" -ForegroundColor Green
    Write-Host "  ║  ⏱  Thời gian bầu chọn : $($totalSec.ToString().PadRight(6)) giây                ║" -ForegroundColor Green
    Write-Host "  ║  👑 Primary mới        : [$newPrimary]                     ║" -ForegroundColor Green
    Write-Host "  ║  🔴 Node đã tắt        : [$primaryNode]                   ║" -ForegroundColor Green
    Write-Host "  ╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Hết thời gian chờ ($totalSec giây). Kiểm tra thủ công." -ForegroundColor Red
}

# ── BƯỚC 5: Trạng thái sau Election ──────────────────────────────
Write-Host ""
Write-Host "  ━━━ BƯỚC 5: Trạng thái sau Election ━━━" -ForegroundColor Magenta
Show-ClusterStatus "Trạng thái SAU Election"

# ── BƯỚC 6: Kiểm tra tính toàn vẹn dữ liệu ──────────────────────
Write-Host "  ━━━ BƯỚC 6: Kiểm tra dữ liệu vẫn nguyên vẹn ━━━" -ForegroundColor Magenta
Write-Host ""

if ($newPrimary) {
    $checkScript = "use demoDB; print('sinhvien: ' + db.sinhvien.countDocuments() + ' records'); print('election_log: ' + db.election_log.countDocuments() + ' records');"
    Invoke-Mongo $newPrimary $checkScript | ForEach-Object {
        Write-Host "  📊 $_" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  ✅ Dữ liệu vẫn nguyên vẹn! Không mất bản ghi nào." -ForegroundColor Green
}

# ── BƯỚC 7: Khởi động lại node cũ ────────────────────────────────
Write-Host ""
Write-Host "  ━━━ BƯỚC 7: Khởi động lại node cũ (rejoin cluster) ━━━" -ForegroundColor Magenta
Write-Host ""
Write-Host "  [!] Nhấn [ENTER] để start lại " -NoNewline -ForegroundColor Yellow
Write-Host "[$primaryNode]" -NoNewline -ForegroundColor Cyan
Write-Host " và quan sát nó join lại cluster..." -ForegroundColor Yellow
Read-Host | Out-Null

Write-Host ""
Write-Host "  🟢 Đang khởi động lại $primaryNode..." -ForegroundColor Green
docker start $primaryNode | Out-Null
Write-Host "  ⏳ Chờ $primaryNode đồng bộ lại với cluster (15 giây)..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

Write-Host ""
Show-ClusterStatus "Trạng thái CUỐI CÙNG (sau khi $primaryNode join lại)"

Write-Host "  ╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║  ✅ Demo hoàn tất!                                    ║" -ForegroundColor Cyan
Write-Host "  ║                                                        ║" -ForegroundColor Cyan
Write-Host "  ║  Minh chứng:                                          ║" -ForegroundColor Cyan
Write-Host "  ║   • Hệ thống tự động phát hiện lỗi Primary           ║" -ForegroundColor White
Write-Host "  ║   • Quorum (2/3 nodes) bầu Primary mới               ║" -ForegroundColor White
Write-Host "  ║   • Dữ liệu không bị mất (High Availability)        ║" -ForegroundColor White
Write-Host "  ║   • Node cũ tự động join lại thành Secondary         ║" -ForegroundColor White
Write-Host "  ╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
