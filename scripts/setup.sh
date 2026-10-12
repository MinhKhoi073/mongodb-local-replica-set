#!/usr/bin/env bash
# ================================================================
#  setup.sh  –  Thiết lập MongoDB Replica Set (WSL / Linux / macOS)
#
#  Đề tài 21: CSDL NoSQL phân tán cục bộ
#  Sinh viên : Nguyễn Minh Khôi – MSSV: 49.01.104.073
#
#  Cách dùng:
#    bash scripts/setup.sh           # Khởi tạo lần đầu
#    bash scripts/setup.sh --reset   # Xóa sạch và tạo lại
# ================================================================

set -euo pipefail

# ── Màu sắc ───────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;37m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KEYFILE="$PROJECT_DIR/mongo-keyfile"
INIT_JS="$SCRIPT_DIR/init-replica.js"
RESET=${1:-""}

log_h()   { echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}";
            echo -e "${CYAN}  $1${NC}";
            echo -e "${CYAN}══════════════════════════════════════════════════${NC}"; }
log_step(){ echo -e "${YELLOW}  ▶ $1${NC}"; }
log_ok()  { echo -e "${GREEN}  ✓ $1${NC}"; }
log_warn(){ echo -e "${YELLOW}  ⚠ $1${NC}"; }
log_fail(){ echo -e "${RED}  ✗ $1${NC}"; exit 1; }

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  MongoDB Replica Set – Setup (WSL / Linux)              ║${NC}"
echo -e "${CYAN}║  Đề tài 21 | Nguyễn Minh Khôi | 49.01.104.073         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"

# ── 1. Kiểm tra Docker ────────────────────────────────────────────
log_h "1/7 – Kiểm tra Docker"
log_step "Kiểm tra docker..."
command -v docker &>/dev/null || log_fail "Docker chưa cài!"
docker info &>/dev/null       || log_fail "Docker daemon chưa chạy!"
log_ok "Docker OK"

# ── 2. Tạo Keyfile ────────────────────────────────────────────────
log_h "2/7 – Keyfile bảo mật"

if [[ "$RESET" == "--reset" ]] || [[ ! -f "$KEYFILE" ]] || [[ $(wc -c < "$KEYFILE") -lt 50 ]]; then
    log_step "Tạo mongo-keyfile ngẫu nhiên (openssl)..."
    openssl rand -base64 756 | tr -d '\n\r' > "$KEYFILE"
    chmod 400 "$KEYFILE"
    log_ok "Keyfile đã tạo: $KEYFILE"
else
    log_ok "Keyfile đã tồn tại ($(wc -c < "$KEYFILE") bytes)"
fi

# ── 3. Reset (nếu yêu cầu) ───────────────────────────────────────
log_h "3/7 – Reset"
if [[ "$RESET" == "--reset" ]]; then
    log_step "Xóa containers và volumes cũ..."
    cd "$PROJECT_DIR"
    docker compose down -v 2>/dev/null || true
    log_ok "Đã xóa dữ liệu cũ"
else
    log_warn "Bỏ qua – dùng --reset để xóa sạch"
fi

# ── 4. Khởi động containers ───────────────────────────────────────
log_h "4/7 – Khởi động 3 nodes MongoDB"
log_step "docker compose up -d..."
cd "$PROJECT_DIR"
docker compose up -d
log_ok "3 containers đã khởi động"

# ── 5. Chờ nodes sẵn sàng ────────────────────────────────────────
log_h "5/7 – Chờ MongoDB sẵn sàng (30–60 giây)"

for NODE in mongo1 mongo2 mongo3; do
    log_step "Chờ $NODE..."
    ready=false
    for i in $(seq 1 30); do
        if docker exec "$NODE" mongosh --eval "db.adminCommand('ping').ok" --quiet 2>/dev/null | grep -q "^1"; then
            ready=true; break
        fi
        printf "    [%d/30] đang chờ...\r" "$i"
        sleep 2
    done
    echo ""
    $ready && log_ok "$NODE sẵn sàng" || log_fail "$NODE không phản hồi! Xem: docker logs $NODE"
done

# ── 6. Khởi tạo Replica Set ──────────────────────────────────────
log_h "6/7 – Khởi tạo Replica Set rs0"
log_step "Sao chép init-replica.js vào mongo1..."
docker cp "$INIT_JS" mongo1:/tmp/init-replica.js

log_step "Chạy rs.initiate()..."
docker exec mongo1 mongosh \
    -u admin -p AdminPass123 \
    --authenticationDatabase admin \
    /tmp/init-replica.js

log_ok "Replica Set rs0 khởi tạo thành công!"

# ── 7. Seed dữ liệu demo ─────────────────────────────────────────
log_h "7/7 – Chèn dữ liệu Demo"
log_step "Thêm bản ghi vào demoDB.sinhvien..."

docker exec mongo1 mongosh \
    -u admin -p AdminPass123 \
    --authenticationDatabase admin \
    --quiet \
    --eval '
use demoDB;
if (db.sinhvien.countDocuments() === 0) {
  db.sinhvien.insertMany([
    { ten:"Nguyen Van A", mssv:"001", khoa:"CNTT", gpa:8.5 },
    { ten:"Tran Thi B",   mssv:"002", khoa:"CNTT", gpa:9.0 },
    { ten:"Le Van C",     mssv:"003", khoa:"CNTT", gpa:7.5 },
    { ten:"Pham Thi D",   mssv:"004", khoa:"CNTT", gpa:8.8 },
    { ten:"Hoang Van E",  mssv:"005", khoa:"CNTT", gpa:7.0 }
  ]);
  print("Da chen " + db.sinhvien.countDocuments() + " ban ghi.");
} else {
  print("Da co " + db.sinhvien.countDocuments() + " ban ghi. Bo qua.");
}
'

log_ok "Dữ liệu demo đã sẵn sàng!"

# ── Xong! ─────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  HOÀN TẤT! Replica Set rs0 đã sẵn sàng                 ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "║  mongo1 (Primary)   → localhost:27017                    ║"
echo -e "║  mongo2 (Secondary) → localhost:27018                    ║"
echo -e "║  mongo3 (Secondary) → localhost:27019                    ║"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${YELLOW}║  Lệnh tiếp theo:                                        ║${NC}"
echo -e "║   bash scripts/check-status.sh                           ║"
echo -e "║   bash scripts/demo-election.sh                          ║"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
