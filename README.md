# MongoDB Local Replica Set – Đề tài 21

> **Sinh viên:** Nguyễn Minh Khôi &nbsp;·&nbsp; **MSSV:** 49.01.104.073  
> **Môn học:** Điện toán đám mây &nbsp;·&nbsp; **Đề tài 21:** Tìm hiểu và triển khai CSDL NoSQL (MongoDB) phân tán cục bộ

---

## 📋 Mục tiêu đề tài

| # | Mục tiêu | Trạng thái |
|---|----------|-----------|
| 1 | Cài đặt MongoDB Replica Set 3 nodes (1 Primary + 2 Secondary) | ✅ |
| 2 | Xác thực nội bộ bằng Keyfile (Shared Secret) | ✅ |
| 3 | Đồng bộ dữ liệu tự động qua cơ chế **oplog replication** | ✅ |
| 4 | Thử nghiệm tắt Primary → quan sát **Election** tự động | ✅ |
| 5 | Node cũ tự join lại cluster sau khi khởi động | ✅ |

---

## 🏗 Kiến trúc hệ thống

```
Windows Host (Docker Desktop + WSL2)
│
├── Docker Bridge Network: mongo-replica-net (172.20.0.0/16)
│   │
│   ├── mongo1 (PRIMARY)    172.20.0.11  ←→ host:27017
│   │    └── oplog ──────────────────────────────────────┐
│   │                                                     │ Keyfile Auth
│   ├── mongo2 (SECONDARY)  172.20.0.12  ←→ host:27018  │ (Shared Secret)
│   │    └── replicates oplog ◄──────────────────────────┤
│   │                                                     │
│   └── mongo3 (SECONDARY)  172.20.0.13  ←→ host:27019  │
│        └── replicates oplog ◄──────────────────────────┘
│
└── Volumes: mongo1-data, mongo2-data, mongo3-data (persistent)
```

**Cơ chế Election (Raft-based):**
```
Primary bị tắt  →  Secondary phát hiện heartbeat timeout (~10s)
                →  Gọi election (cần quorum: 2/3 nodes đồng ý)
                →  Node có priority cao nhất được bầu làm Primary mới
                →  Toàn bộ quá trình: 5–15 giây
```

---

## ⚙️ Yêu cầu hệ thống

| Phần mềm | Phiên bản | Ghi chú |
|----------|-----------|---------|
| Docker Desktop | ≥ 4.x | Bật WSL2 backend |
| Windows OS | 10/11 | WSL2 phải được kích hoạt |
| RAM khả dụng | ≥ 3 GB | ~1 GB / container |
| Disk | ≥ 5 GB | Cho volumes + images |

---

## 🚀 Quick Start (Windows PowerShell)

```powershell
# 1. Clone repo
git clone https://github.com/<your-username>/mongodb-local-replica-set
cd mongodb-local-replica-set

# 2. Chạy script setup tự động (tất cả trong 1 lệnh)
.\scripts\setup.ps1

# 3. Kiểm tra trạng thái cluster
.\scripts\check-status.ps1

# 4. Chạy Live Demo Election
.\scripts\demo-election.ps1
```

**WSL / Linux:**
```bash
bash scripts/setup.sh
bash scripts/check-status.sh   # (nếu có)
bash scripts/demo-election.sh
```

---

## 📂 Cấu trúc thư mục

```
mongodb-local-replica-set/
│
├── docker-compose.yml          # Định nghĩa 3 container MongoDB + network + volumes
├── mongo-keyfile               # Shared Secret key (tạo tự động bởi setup.ps1)
├── .gitignore
│
└── scripts/
    ├── init-replica.js         # mongosh script: rs.initiate() + chờ election
    ├── setup.ps1               # 🪟 Windows: setup đầy đủ tự động
    ├── setup.sh                # 🐧 WSL/Linux: setup đầy đủ tự động
    ├── demo-election.ps1       # 🪟 Windows: Live Demo cho Hội đồng
    ├── demo-election.sh        # 🐧 WSL/Linux: Live Demo
    └── check-status.ps1        # 🪟 Kiểm tra nhanh trạng thái cluster
```

---

## 🔧 Hướng dẫn chi tiết từng bước

### Bước 1 – Chuẩn bị

Đảm bảo Docker Desktop đang chạy:
```powershell
docker --version
docker info
```

### Bước 2 – Tạo Keyfile bảo mật

Script `setup.ps1` tự động tạo keyfile bằng `RandomNumberGenerator` của .NET:
```powershell
# Thủ công (nếu muốn):
$bytes = New-Object byte[] 756
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
[Convert]::ToBase64String($bytes) | Set-Content .\mongo-keyfile -Encoding ASCII -NoNewline
```

### Bước 3 – Khởi động cluster

```powershell
docker compose up -d

# Kiểm tra logs
docker logs mongo1 --tail 30
docker logs mongo2 --tail 10
```

### Bước 4 – Khởi tạo Replica Set

```powershell
# Sao chép script vào container
docker cp scripts/init-replica.js mongo1:/tmp/

# Chạy rs.initiate()
docker exec mongo1 mongosh -u admin -p AdminPass123 `
    --authenticationDatabase admin /tmp/init-replica.js
```

### Bước 5 – Kiểm tra đồng bộ dữ liệu

```javascript
// Kết nối Primary (port 27017) và ghi dữ liệu:
mongosh "mongodb://admin:AdminPass123@localhost:27017/admin?replicaSet=rs0"
use demoDB
db.test.insertOne({ message: "Hello Replica Set!", ts: new Date() })

// Kết nối Secondary (port 27018) và đọc lại:
// (thêm readPreference=secondary vào URI)
mongosh "mongodb://admin:AdminPass123@localhost:27018/admin?replicaSet=rs0&readPreference=secondary"
use demoDB
db.test.find()   // Bản ghi vừa ghi ở Primary đã xuất hiện ✅
```

---

## 🎬 Kịch bản Live Demo

> **Mở 3 Terminal** song song để demo trực quan nhất:

```
Terminal 1: .\scripts\demo-election.ps1    ← Script demo chính
Terminal 2: docker stats                   ← Theo dõi tài nguyên containers
Terminal 3: mongosh (kết nối cluster)      ← Query thủ công nếu cần
```

### Trình tự demo trước Hội đồng:

| Bước | Hành động | Kết quả kỳ vọng |
|------|-----------|-----------------|
| 1 | Chạy `demo-election.ps1` | Hiện trạng thái ban đầu: mongo1=PRIMARY |
| 2 | Xem `rs.status()` | 3 nodes, 1 PRIMARY, 2 SECONDARY |
| 3 | Nhấn **ENTER** để tắt Primary | Script tự `docker stop mongo1` |
| 4 | Quan sát output real-time | Election diễn ra trong **5–15 giây** |
| 5 | Primary mới được bầu | mongo2 hoặc mongo3 trở thành PRIMARY |
| 6 | Kiểm tra dữ liệu | Không mất bản ghi nào |
| 7 | Nhấn **ENTER** để start lại mongo1 | mongo1 join lại thành SECONDARY |

### Lệnh mongosh thủ công (để demo thêm):

```javascript
// Xem trạng thái tổng quan
rs.status()

// Xem ai là Primary
rs.isMaster()

// Xem oplog (nhật ký đồng bộ)
use local
db.oplog.rs.find().sort({$natural:-1}).limit(5)

// Thống kê replication lag
rs.printReplicationInfo()
rs.printSecondaryReplicationInfo()
```

---

## 🔒 Bảo mật – Keyfile Authentication

MongoDB yêu cầu tất cả nodes trong Replica Set phải có **cùng một keyfile**:

```yaml
# docker-compose.yml (đã cấu hình sẵn)
volumes:
  - ./mongo-keyfile:/auth/keyfile:ro   # Mount keyfile vào container

command:
  - mongod --replSet rs0 --keyFile /tmp/keyfile ...
```

- Keyfile được **sinh ngẫu nhiên** (756 bytes → Base64) mỗi lần chạy `setup.ps1 -Reset`
- Chỉ container có keyfile hợp lệ mới được phép join cluster
- External client vẫn dùng **username/password** (admin/AdminPass123)

---

## 🛠 Xử lý sự cố thường gặp

### Lỗi: `AuthenticationFailed`
```powershell
# Kiểm tra user đã tồn tại chưa
docker exec mongo1 mongosh --eval "db.adminCommand('listUsers')"

# Nếu cluster mới, chạy lại toàn bộ từ đầu:
.\scripts\setup.ps1 -Reset
```

### Lỗi: `Connection refused`
```powershell
# Kiểm tra container có đang chạy không
docker ps -a

# Xem log lỗi
docker logs mongo1 --tail 50
```

### Lỗi: `keyfile too short` hoặc `bad characters`
```powershell
# Tạo lại keyfile
.\scripts\setup.ps1 -Reset
```

### Replica Set không bầu được Primary
```powershell
# Kiểm tra quorum (cần ít nhất 2/3 nodes ONLINE)
.\scripts\check-status.ps1

# Khởi động node bị tắt
docker start mongo2
docker start mongo3
```

### Xóa sạch và bắt đầu lại
```powershell
docker compose down -v        # Xóa containers + volumes
.\scripts\setup.ps1 -Reset   # Tạo lại từ đầu
```

---

## 📊 Các lệnh hữu ích

```powershell
# Khởi động / dừng cluster
docker compose up -d
docker compose down

# Xem logs
docker logs mongo1 -f

# Kết nối trực tiếp vào node
docker exec -it mongo1 mongosh -u admin -p AdminPass123 --authenticationDatabase admin

# Xem thống kê resources
docker stats mongo1 mongo2 mongo3

# Kết nối bằng MongoDB Compass
# URI: mongodb://admin:AdminPass123@localhost:27017,localhost:27018,localhost:27019/admin?replicaSet=rs0
```

---

## 📚 Tài liệu tham khảo

- [MongoDB Replica Set Documentation](https://www.mongodb.com/docs/manual/replication/)
- [MongoDB Keyfile Authentication](https://www.mongodb.com/docs/manual/tutorial/deploy-replica-set-with-keyfile-access-control/)
- [Docker Compose Reference](https://docs.docker.com/compose/)
- [MongoDB Election Mechanics](https://www.mongodb.com/docs/manual/core/replica-set-elections/)

---

*Đề tài 21 – Học kỳ 2025–2026 | Khoa Công nghệ Thông tin*