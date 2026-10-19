#!/usr/bin/env bash
# ================================================================
#  demo-election.sh  –  Live Demo: MongoDB Election (WSL/Linux)
#
#  Cách chạy: bash scripts/demo-election.sh
# ================================================================

MONGO_USER="admin"; MONGO_PASS="AdminPass123"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
GRAY='\033[0;37m'; BOLD='\033[1m'; NC='\033[0m'

mongo_exec() { docker exec "$1" mongosh -u "$MONGO_USER" -p "$MONGO_PASS" \
    --authenticationDatabase admin --quiet --eval "$2" 2>/dev/null; }

show_status() {
    local title="${1:-Trang thai}"
    local members from_node
    echo ""
    echo -e "${YELLOW}  ┌─ $title ──────────────────────────────────────────${NC}"
    for node in mongo1 mongo2 mongo3; do
        [[ "$(docker inspect "$node" --format '{{.State.Status}}' 2>/dev/null)" != "running" ]] && continue
        members=$(mongo_exec "$node" \
            "rs.status().members.forEach(m=>print(m.name+'|'+m.stateStr+'|'+m.health))" 2>/dev/null)
        if [[ -n "$members" ]]; then
            from_node=$node
            while IFS='|' read -r name state health; do
                short="${name%%:*}"
                port="${name##*:}"
                case "$state" in
                    PRIMARY)   echo -e "${YELLOW}  │${NC}  ${GREEN}👑 ${BOLD}${short}${NC}${GREEN}  :${port}  →  PRIMARY   ${NC}" ;;
                    SECONDARY) echo -e "${YELLOW}  │${NC}  ${BLUE}🔄 ${short}  :${port}  →  SECONDARY ${NC}" ;;
                    *)         echo -e "${YELLOW}  │${NC}  ${RED}❓ ${short}  :${port}  →  $state ${NC}" ;;
                esac
            done <<< "$members"
            echo -e "${YELLOW}  │  ${GRAY}(query từ: $from_node)${NC}"
            break
        fi
    done
    echo -e "${YELLOW}  └────────────────────────────────────────────────────────${NC}"
    echo ""
}

find_primary() {
    for node in mongo1 mongo2 mongo3; do
        [[ "$(docker inspect "$node" --format '{{.State.Status}}' 2>/dev/null)" != "running" ]] && continue
        result=$(mongo_exec "$node" "db.hello().isWritablePrimary" 2>/dev/null)
        [[ "$result" == *"true"* ]] && echo "$node" && return 0
    done
    return 1
}

# ══════════════════════════════════════════════════════════════════
clear
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   LIVE DEMO: MongoDB Replica Set – Automatic Election   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"

# ── BƯỚC 1 ────────────────────────────────────────────────────────
echo ""
echo -e "${MAGENTA}  ━━━ BƯỚC 1: Trạng thái ban đầu ━━━${NC}"
show_status "Trạng thái TRƯỚC Election"

primary=$(find_primary) || { echo -e "${RED}  ❌ Không tìm thấy Primary!${NC}"; exit 1; }
echo -e "  🎯 Primary hiện tại: ${GREEN}${BOLD}[$primary]${NC}"

# ── BƯỚC 2 ────────────────────────────────────────────────────────
echo ""
echo -e "${MAGENTA}  ━━━ BƯỚC 2: Ghi dữ liệu vào Primary trước khi tắt ━━━${NC}"
ts=$(date "+%Y-%m-%d %H:%M:%S")
mongo_exec "$primary" \
    "use demoDB; db.election_log.insertOne({event:'BEFORE_ELECTION',primary:'$primary',ts:'$ts'}); print('Ghi thanh cong.');"
echo -e "  ${GREEN}✅ Đã ghi 1 bản ghi vào Primary ($primary)${NC}"

# ── PAUSE ─────────────────────────────────────────────────────────
echo ""
echo -e "${RED}  ┌─────────────────────────────────────────────────────────┐${NC}"
echo -e "${RED}  │  ⚡ Nhấn [ENTER] để TẮT PRIMARY ngay bây giờ!         │${NC}"
echo -e "${RED}  └─────────────────────────────────────────────────────────┘${NC}"
read -r

# ── BƯỚC 3 ────────────────────────────────────────────────────────
echo ""
echo -e "${RED}  ━━━ BƯỚC 3: Tắt Node Primary ━━━${NC}"
echo -e "${RED}  ⏹  Đang dừng: $primary ...${NC}"
docker stop "$primary" > /dev/null
echo -e "${RED}  🔴 Container [$primary] ĐÃ DỪNG!${NC}"
echo -e "${YELLOW}  🕐 Bắt đầu đo thời gian Election...${NC}"
election_start=$(date +%s%3N)

# ── BƯỚC 4: Real-time election monitor ───────────────────────────
echo ""
echo -e "${MAGENTA}  ━━━ BƯỚC 4: Quan sát Election (real-time) ━━━${NC}"
echo -e "${GRAY}  (Cần quorum ≥ 2/3 nodes để bầu Primary mới)${NC}"
echo ""

query_node=$([ "$primary" = "mongo1" ] && echo "mongo2" || echo "mongo1")
new_primary=""
max_ms=30000

while true; do
    now=$(date +%s%3N)
    elapsed_ms=$(( now - election_start ))
    elapsed_s=$(echo "scale=1; $elapsed_ms/1000" | bc)

    raw=$(docker exec "$query_node" mongosh -u "$MONGO_USER" -p "$MONGO_PASS" \
        --authenticationDatabase admin --quiet --eval \
        "rs.status().members.forEach(m=>print(m.name+'|'+m.stateStr))" 2>/dev/null)

    if [[ -n "$raw" ]]; then
        printf "  [%5ss] " "$elapsed_s"
        while IFS='|' read -r name state; do
            short="${name%%:*}"
            case "$state" in
                PRIMARY)   printf "${GREEN}%s:👑PRIMARY   ${NC}  " "$short" ;;
                SECONDARY) printf "${BLUE}%s:🔄SECONDARY${NC}  " "$short" ;;
                *)         printf "${YELLOW}%s:%s${NC}  " "$short" "$state" ;;
            esac
        done <<< "$raw"
        echo ""

        new_p=$(echo "$raw" | awk -F'|' '$2=="PRIMARY"{print $1}' | cut -d: -f1)
        if [[ -n "$new_p" && "$new_p" != "$primary" ]]; then
            new_primary=$new_p; break
        fi
    else
        printf "  [%5ss] Đang bầu chọn...\n" "$elapsed_s"
    fi

    [[ $elapsed_ms -ge $max_ms ]] && break
    sleep 0.5
done

total_s=$(echo "scale=2; ($(date +%s%3N) - election_start)/1000" | bc)
echo ""
if [[ -n "$new_primary" ]]; then
    echo -e "${GREEN}  ╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}  ║  🎉 ELECTION THÀNH CÔNG!                              ║${NC}"
    echo -e "${GREEN}  ║  ⏱  Thời gian bầu chọn : ${total_s}s                       ║${NC}"
    echo -e "${GREEN}  ║  👑 Primary mới        : [$new_primary]                     ║${NC}"
    echo -e "${GREEN}  ║  🔴 Node đã tắt        : [$primary]                   ║${NC}"
    echo -e "${GREEN}  ╚════════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${RED}  ⚠ Hết thời gian. Kiểm tra thủ công với rs.status()${NC}"
fi

# ── BƯỚC 5–7 ──────────────────────────────────────────────────────
echo ""
echo -e "${MAGENTA}  ━━━ BƯỚC 5: Trạng thái sau Election ━━━${NC}"
show_status "Trạng thái SAU Election"

echo -e "${MAGENTA}  ━━━ BƯỚC 6: Kiểm tra tính toàn vẹn dữ liệu ━━━${NC}"
echo ""
[[ -n "$new_primary" ]] && mongo_exec "$new_primary" \
    "use demoDB; print('sinhvien: '+db.sinhvien.countDocuments()+' records'); print('election_log: '+db.election_log.countDocuments()+' records');" | \
    while read -r line; do echo -e "  📊 ${line}"; done
echo ""
echo -e "  ${GREEN}✅ Dữ liệu vẫn nguyên vẹn!${NC}"

echo ""
echo -e "${YELLOW}  [!] Nhấn [ENTER] để start lại [$primary] (rejoin cluster)...${NC}"
read -r
docker start "$primary" > /dev/null
echo -e "  ${GREEN}🟢 $primary đã khởi động lại${NC}"
sleep 15

echo ""
echo -e "${MAGENTA}  ━━━ BƯỚC 7: Trạng thái cuối cùng ━━━${NC}"
show_status "Trạng thái CUỐI CÙNG"

echo -e "${CYAN}  ╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}  ║  ✅ Demo hoàn tất! MongoDB hoạt động chính xác.   ║${NC}"
echo -e "${CYAN}  ╚════════════════════════════════════════════════════════╝${NC}"
echo ""
