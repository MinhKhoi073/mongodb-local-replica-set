# ================================================================
#  setup.ps1 - Thiet lap MongoDB Replica Set tren Windows
#
#  Cach dung:
#    .\scripts\setup.ps1              # Khoi tao lan dau hoac chay lai
#    .\scripts\setup.ps1 -Reset       # Xoa sach toan bo du lieu cu va tao moi
# ================================================================

param(
    [switch]$Reset
)

$ErrorActionPreference = "Continue"

function Write-Header ([string]$Text) {
    Write-Host ""
    Write-Host ("==============================================================") -ForegroundColor Cyan
    Write-Host ("  " + $Text) -ForegroundColor Cyan
    Write-Host ("==============================================================") -ForegroundColor Cyan
}
function Write-Step ([string]$T) { Write-Host ("  [>] " + $T) -ForegroundColor Yellow }
function Write-OK   ([string]$T) { Write-Host ("  [OK] " + $T) -ForegroundColor Green  }
function Write-Warn ([string]$T) { Write-Host ("  [!] " + $T) -ForegroundColor DarkYellow }
function Write-Fail ([string]$T) { Write-Host ("  [X] " + $T) -ForegroundColor Red; exit 1 }

$ScriptDir   = $PSScriptRoot
$ProjectDir  = Split-Path $ScriptDir -Parent
$KeyfilePath = Join-Path $ProjectDir "mongo-keyfile"
$InitScript  = Join-Path $ScriptDir  "init-replica.js"

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "   MongoDB Replica Set - Thiet lap moi truong Cluster         " -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan

# -- Buoc 1: Kiem tra Docker Desktop -------------------------------
Write-Header "Buoc 1/7 - Kiem tra Docker Desktop"
Write-Step "Kiem tra Docker CLI..."

try {
    $dVer = docker --version
    Write-OK ("Docker CLI OK: " + $dVer)
} catch {
    Write-Fail "Docker chua cai dat! Vui long tai tai https://www.docker.com/products/docker-desktop"
}

Write-Step "Kiem tra Docker daemon..."
try {
    docker info 2>&1 | Out-Null
    Write-OK "Docker daemon dang hoat dong tot"
} catch {
    Write-Fail "Docker Desktop chua bat! Vui long mo Docker Desktop roi chay lai."
}

# -- Buoc 2: Tao/Kiem tra Keyfile ----------------------------------
Write-Header "Buoc 2/7 - Keyfile bao mat (Shared Secret)"

$needNewKey = $Reset -or !(Test-Path $KeyfilePath)
if (-not $needNewKey) {
    if ((Get-Item $KeyfilePath).Length -lt 50) { $needNewKey = $true }
}

if ($needNewKey) {
    Write-Step "Tao file mongo-keyfile ngau nhien (756 bytes, Base64)..."
    $rng   = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 756
    $rng.GetBytes($bytes)
    $b64   = [Convert]::ToBase64String($bytes)
    $cleanB64 = $b64 -replace "`r|`n", ""
    [System.IO.File]::WriteAllText($KeyfilePath, $cleanB64, [System.Text.Encoding]::ASCII)
    Write-OK ("Da tao keyfile moi tai: " + $KeyfilePath)
} else {
    $kLen = (Get-Item $KeyfilePath).Length
    Write-OK ("Keyfile da ton tai hop le (" + $kLen + " bytes)")
}

# -- Buoc 3: Reset du lieu cu ----------------------
if ($Reset) {
    Write-Header "Buoc 3/7 - Xoa du lieu va volume cu (-Reset)"
    Write-Step "Dang xoa containers va volumes..."
    Push-Location $ProjectDir
    docker compose down -v 2>&1 | Out-Null
    Pop-Location
    Write-OK "Da don dep sach toan bo containers va volumes"
} else {
    Write-Header "Buoc 3/7 - Giu nguyen du lieu (khong dung -Reset)"
    Write-Warn "Giu nguyen du lieu va volumes hien tai"
}

# -- Buoc 4: Khoi dong containers ----------------------------------
Write-Header "Buoc 4/7 - Khoi dong 3 nodes MongoDB"
Write-Step "Dang chay docker compose up -d..."

Push-Location $ProjectDir
docker compose up -d
$composeExit = $LASTEXITCODE
Pop-Location

if ($composeExit -ne 0) {
    Write-Fail "Loi khi khoi dong Docker Compose! Kiem tra lai docker-compose.yml"
}
Write-OK "3 containers (mongo1, mongo2, mongo3) da khoi dong"

# -- Buoc 5: Cho cac nodes san sang --------------------------------
Write-Header "Buoc 5/7 - Cho MongoDB khoi tao (20-40 giay)"

foreach ($Node in @("mongo1", "mongo2", "mongo3")) {
    Write-Step ("Dang cho node " + $Node + " mo cong...")
    $ready = $false

    for ($i = 1; $i -le 30; $i++) {
        $out = docker exec $Node mongosh --eval "db.adminCommand('ping').ok" --quiet 2>&1
        if ($out -match "^1") {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 2
        Write-Host ("    [" + $i + "/30] Dang kiem tra...") -ForegroundColor DarkGray
    }

    if ($ready) {
        Write-OK ("Node " + $Node + " da san sang ket noi")
    } else {
        Write-Fail ("Node " + $Node + " khong phan hoi! Xem log: docker logs " + $Node)
    }
}

# -- Buoc 6: Khoi tao Replica Set ----------------------------------
Write-Header "Buoc 6/7 - Khoi tao Replica Set rs0"
Write-Step "Sao chep init-replica.js vao container mongo1..."
docker cp $InitScript mongo1:/tmp/init-replica.js

Write-Step "Thuc thi rs.initiate() tren mongo1..."
docker exec mongo1 mongosh -u admin -p AdminPass123 --authenticationDatabase admin /tmp/init-replica.js

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  Log mongo1 (20 dong cuoi):" -ForegroundColor Red
    docker logs mongo1 --tail 20
    Write-Fail "Loi khi khoi tao Replica Set! Kiem tra log o tren."
}
Write-OK "Replica Set rs0 da khoi tao thanh cong!"

# -- Buoc 7: Chen du lieu mau --------------------------------------
Write-Header "Buoc 7/7 - Chen du lieu Demo mau"
Write-Step "Them du lieu sinh vien vao demoDB.sinhvien..."

$SeedScript = "var dbDemo = db.getSiblingDB('demoDB'); if (dbDemo.sinhvien.countDocuments() === 0) { dbDemo.sinhvien.insertMany([{ ten: 'Nguyen Van A', mssv: '001', khoa: 'CNTT', gpa: 8.5, nam: 3 }, { ten: 'Tran Thi B', mssv: '002', khoa: 'CNTT', gpa: 9.0, nam: 2 }, { ten: 'Le Van C', mssv: '003', khoa: 'CNTT', gpa: 7.5, nam: 4 }, { ten: 'Pham Thi D', mssv: '004', khoa: 'CNTT', gpa: 8.8, nam: 1 }, { ten: 'Hoang Van E', mssv: '005', khoa: 'CNTT', gpa: 7.0, nam: 3 }]); print('Da chen 5 ban ghi sinh vien thanh cong.'); } else { print('Du lieu da ton tai.'); }"

docker exec mongo1 mongosh -u admin -p AdminPass123 --authenticationDatabase admin --quiet --eval "$SeedScript"

Write-OK "Du lieu demo da san sang trong CSDL demoDB!"

# -- Hoan tat ------------------------------------------------------
Write-Host ""
Write-Host "==============================================================" -ForegroundColor Green
Write-Host "   HOAN TAT! MongoDB Replica Set rs0 da san sang 100%!       " -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Green
Write-Host "   * mongo1 (Primary)    -> localhost:27017                   " -ForegroundColor White
Write-Host "   * mongo2 (Secondary)  -> localhost:27018                   " -ForegroundColor White
Write-Host "   * mongo3 (Secondary)  -> localhost:27019                   " -ForegroundColor White
Write-Host "--------------------------------------------------------------" -ForegroundColor Green
Write-Host "   Lenh kiem tra tiep theo:                                   " -ForegroundColor Yellow
Write-Host "    .\scripts\check-status.ps1      # Kiem tra nhanh suc khoe" -ForegroundColor Cyan
Write-Host "    .\scripts\demo-election.ps1     # Chay Live Demo Election" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Green
Write-Host ""
