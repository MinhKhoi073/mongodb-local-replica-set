/**
 * init-replica.js  –  Khởi tạo MongoDB Replica Set (rs0)

 * Cách chạy (sau khi docker compose up -d):
 *   docker cp scripts/init-replica.js mongo1:/tmp/
 *   docker exec mongo1 mongosh -u admin -p AdminPass123 \
 *       --authenticationDatabase admin /tmp/init-replica.js
 *
 * Hoặc dùng setup.ps1 / setup.sh để tự động hóa toàn bộ.
 */

// ─── Banner ────────────────────────────────────────────────────────
print("");
print("══════════════════════════════════════════════════════════════");
print("  Khoi tao MongoDB Replica Set (rs0)");
print("  Cau hinh: 1 Primary + 2 Secondary + Keyfile Auth");
print("══════════════════════════════════════════════════════════════");
print("");

// ─── Cấu hình Replica Set ─────────────────────────────────────────
const rsConfig = {
  _id: "rs0",
  members: [
    { _id: 0, host: "mongo1:27017", priority: 2 },
    { _id: 1, host: "mongo2:27017", priority: 1 },
    { _id: 2, host: "mongo3:27017", priority: 1 }
  ]
};

print("[1/4] Cau hinh Replica Set:");
rsConfig.members.forEach(m =>
  print("      _id:" + m._id + "  host:" + m.host + "  priority:" + m.priority)
);

// ─── rs.initiate() ────────────────────────────────────────────────
print("");
print("[2/4] Dang goi rs.initiate()...");

try {
  const result = rs.initiate(rsConfig);
  if (result.ok === 1) {
    print("      rs.initiate() thanh cong! (ok:1)");
  } else {
    printjson(result);
  }
} catch (e) {
  const msg = e.message || String(e);
  if (msg.toLowerCase().includes("already") || e.codeName === "AlreadyInitialized") {
    print("      Replica Set da duoc khoi tao truoc do. Tiep tuc...");
  } else {
    print("      LOI: " + msg);
    quit(1);
  }
}

// ─── Chờ Primary được bầu chọn ───────────────────────────────────
print("");
print("[3/4] Dang cho Primary duoc bau chon (toi da 60s)...");

let electedPrimary = null;
let waitSeconds = 0;

for (let attempt = 0; attempt < 30; attempt++) {
  sleep(2000);
  waitSeconds += 2;

  try {
    const status = rs.status();
    if (!status.members) continue;

    const primary = status.members.find(m => m.stateStr === "PRIMARY");
    if (primary) {
      electedPrimary = primary.name;
      print("      Primary da bau chon sau ~" + waitSeconds + "s: " + primary.name);
      break;
    }

    // In trang thai ngan gon moi vong
    const summary = status.members.map(m =>
      m.name.split(":")[0] + ":" + m.stateStr.substring(0, 4)
    ).join("  |  ");
    print("      [" + waitSeconds + "s] " + summary);

  } catch (e) {
    print("      [" + waitSeconds + "s] Dang khoi dong... (" + (e.message || "retry") + ")");
  }
}

if (!electedPrimary) {
  print("      CANH BAO: Het thoi gian. Kiem tra thu cong bang rs.status()");
}

// ─── Hiển thị trạng thái cuối ─────────────────────────────────────
print("");
print("[4/4] Trang thai Replica Set hien tai:");

try {
  const finalStatus = rs.status();
  finalStatus.members.forEach(m => {
    const role = m.stateStr.padEnd(12);
    const name = m.name.padEnd(22);
    const state = m.stateStr === "PRIMARY" ? "[PRIMARY  *]" :
      m.stateStr === "SECONDARY" ? "[SECONDARY ]" :
        "[" + m.stateStr.substring(0, 10) + "]";
    print("      " + name + state);
  });
} catch (e) {
  print("      Khong the lay trang thai: " + e.message);
}

// ─── Kết nối URI ──────────────────────────────────────────────────
print("");
print("══════════════════════════════════════════════════════════════");
print("  Replica Set rs0 san sang!");
print("");
print("  Ket noi URI:");
print("  mongodb://admin:AdminPass123@localhost:27017,localhost:27018,");
print("            localhost:27019/admin?replicaSet=rs0");
print("══════════════════════════════════════════════════════════════");
print("");
