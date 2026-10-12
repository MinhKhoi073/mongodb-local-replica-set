# ================================================================
#  setup.ps1  –  Thiết lập MongoDB Replica Set trên Windows
#
#  Đề tài 21: CSDL NoSQL phân tán cục bộ
#  Sinh viên : Nguyễn Minh Khôi – MSSV: 49.01.104.073
#
#  Cách dùng:
#    .\scripts\setup.ps1              # Khởi tạo lần đầu
#    .\scripts\setup.ps1 -Reset      # Xóa sạch và tạo lại
# ================================================================

param(
    [switch]$Reset   # Nếu có: xóa toàn bộ volume cũ và tạo lại từ đầu
)

$ErrorActionPreference = "Stop"

# ── Màu sắc terminal ──────────────────────────────────────────────
function Write-Header ([string]$Text) {
    $bar = "═" * 62
    Write-Host ""
    Write-Host $bar                -ForegroundColor Cyan
    Write-Host "  $Text"          -ForegroundColor Cyan
    Write-Host $bar                -ForegroundColor Cyan
}
function Write-Step    ([string]$T) { Write-Host "  ▶ $T" -ForegroundColor Yellow }
function Write-OK      ([string]$T) { Write-Host "  ✓ $T" -ForegroundColor Green  }
function Write-Warn    ([string]$T) { Write-Host "  ⚠ $T" -ForegroundColor DarkYellow }
function Write-Fail    ([string]$T) { Write-Host "  ✗ $T" -ForegroundColor Red; exit 1 }

# ── Đường dẫn ─────────────────────────────────────────────────────
$ScriptDir  = $PSScriptRoot
$ProjectDir = Split-Path $ScriptDir -Parent
$KeyfilePath = Join-Path $ProjectDir "mongo-keyfile"
$InitScript  = Join-Path $ScriptDir  "init-replica.js"

# ══════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   MongoDB Replica Set – Thiết lập môi trường                ║" -ForegroundColor Cyan
Write-Host "║   Đề tài 21 | Nguyễn Minh Khôi | MSSV: 49.01.104.073      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# ── Bước 1: Kiểm tra Docker ───────────────────────────────────────
Write-Header "Bước 1/7 – Kiểm tra Docker Desktop"
Write-Step "Kiểm tra docker CLI..."

try   { docker --version | Out-Null; Write-OK "Docker CLI OK" }
catch { Write-Fail "Docker chưa cài! Tải tại https://www.docker.com/products/docker-desktop" }

Write-Step "Kiểm tra Docker daemon..."
try   { docker info 2>&1 | Out-Null; Write-OK "Docker daemon đang chạy" }
catch { Write-Fail "Docker Desktop chưa khởi động! Mở Docker Desktop rồi thử lại." }

# ── Bước 2: Tạo/Kiểm tra Keyfile ─────────────────────────────────
Write-Header "Bước 2/7 – Keyfile bảo mật (Shared Secret)"

if ($Reset -or !(Test-Path $KeyfilePath) -or (Get-Item $KeyfilePath).Length -lt 50) {
    Write-Step "Tạo mongo-keyfile ngẫu nhiên (756 bytes, base64)..."

    $rng   = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 756
    $rng.GetBytes($bytes)
    $b64   = [Convert]::ToBase64String($bytes)
    # Loại bỏ ký tự xuống dòng để MongoDB không cảnh báo
    $b64 -replace "`r|`n", "" | Set-Content -Path $KeyfilePath -Encoding ASCII -NoNewline

    Write-OK "Keyfile đã tạo: $KeyfilePath"
} else {
    Write-OK "Keyfile đã tồn tại ($($(Get-Item $KeyfilePath).Length) bytes)"
}

# ── Bước 3: Reset (nếu yêu cầu) ──────────────────────────────────
if ($Reset) {
    Write-Header "Bước 3/7 – Xóa dữ liệu cũ (--Reset)"
    Write-Step "Xóa containers và volumes..."
    Push-Location $ProjectDir
    docker compose down -v 2>&1 | Out-Null
    Pop-Location
    Write-OK "Đã xóa toàn bộ dữ liệu cũ"
} else {
    Write-Header "Bước 3/7 – Bỏ qua Reset (dùng -Reset để xóa sạch)"
    Write-Warn "Bỏ qua – dữ liệu hiện tại được giữ nguyên"
}

# ── Bước 4: Khởi động containers ─────────────────────────────────
Write-Header "Bước 4/7 – Khởi động 3 nodes MongoDB"
Write-Step "Chạy docker compose up -d..."

Push-Location $ProjectDir
docker compose up -d
if ($LASTEXITCODE -ne 0) { Write-Fail "Lỗi khởi động Docker Compose!" }
Pop-Location
Write-OK "3 containers đã khởi động"

# ── Bước 5: Chờ nodes sẵn sàng ───────────────────────────────────
Write-Header "Bước 5/7 – Chờ MongoDB khởi tạo (30–60 giây)"

foreach ($Node in @("mongo1", "mongo2", "mongo3")) {
    Write-Step "Chờ $Node..."
    $ready = $false

    for ($i = 1; $i -le 30; $i++) {
        $out = docker exec $Node mongosh --eval "db.adminCommand('ping').ok" --quiet 2>&1
        if ($out -match "^1") { $ready = $true; break }
        Start-Sleep -Seconds 2
        Write-Host "    [$i/30] Chờ..." -ForegroundColor DarkGray
    }

    if ($ready) { Write-OK "$Node sẵn sàng" }
    else         { Write-Fail "$Node không phản hồi sau 60 giây! Xem log: docker logs $Node" }
}

# ── Bước 6: Khởi tạo Replica Set ─────────────────────────────────
Write-Header "Bước 6/7 – Khởi tạo Replica Set rs0"
Write-Step "Sao chép init-replica.js vào mongo1..."
docker cp $InitScript mongo1:/tmp/init-replica.js

Write-Step "Chạy rs.initiate() bên trong mongo1..."
docker exec mongo1 mongosh `
    -u admin -p AdminPass123 `
    --authenticationDatabase admin `
    /tmp/init-replica.js

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  Log mongo1 (20 dòng cuối):" -ForegroundColor Red
    docker logs mongo1 --tail 20
    Write-Fail "Lỗi khởi tạo Replica Set!"
}
Write-OK "Replica Set rs0 đã khởi tạo thành công!"

# ── Bước 7: Chèn dữ liệu Demo ────────────────────────────────────
Write-Header "Bước 7/7 – Chèn dữ liệu Demo"
Write-Step "Thêm dữ liệu sinh viên vào demoDB.sinhvien..."

$SeedScript = @'
use demoDB;
const count = db.sinhvien.countDocuments();
if (count === 0) {
  db.sinhvien.insertMany([
    { ten: "Nguyen Van A",  mssv: "001", khoa: "CNTT", gpa: 8.5, nam: 3 },
    { ten: "Tran Thi B",    mssv: "002", khoa: "CNTT", gpa: 9.0, nam: 2 },
    { ten: "Le Van C",      mssv: "003", khoa: "CNTT", gpa: 7.5, nam: 4 },
    { ten: "Pham Thi D",    mssv: "004", khoa: "CNTT", gpa: 8.8, nam: 1 },
    { ten: "Hoang Van E",   mssv: "005", khoa: "CNTT", gpa: 7.0, nam: 3 }
  ]);
  print("Da chen " + db.sinhvien.countDocuments() + " ban ghi moi.");
} else {
  print("Da co " + count + " ban ghi. Bo qua.");
}
'@

docker exec mongo1 mongosh `
    -u admin -p AdminPass123 `
    --authenticationDatabase admin `
    --quiet `
    --eval $SeedScript

Write-OK "Dữ liệu demo đã sẵn sàng!"

# ── Xong! ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   HOÀN TẤT! MongoDB Replica Set rs0 đã sẵn sàng            ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║   mongo1 (Primary)    →  localhost:27017                    ║" -ForegroundColor White
Write-Host "║   mongo2 (Secondary)  →  localhost:27018                    ║" -ForegroundColor White
Write-Host "║   mongo3 (Secondary)  →  localhost:27019                    ║" -ForegroundColor White
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║  Kết nối MongoDB Compass / mongosh:                         ║" -ForegroundColor Yellow
Write-Host "║  mongodb://admin:AdminPass123@localhost:27017,              ║" -ForegroundColor Cyan
Write-Host "║    localhost:27018,localhost:27019/admin?replicaSet=rs0     ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║  Lệnh tiếp theo:                                            ║" -ForegroundColor Yellow
Write-Host "║   .\scripts\check-status.ps1      # Kiểm tra nhanh         ║" -ForegroundColor White
Write-Host "║   .\scripts\demo-election.ps1     # Chạy Live Demo         ║" -ForegroundColor White
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
