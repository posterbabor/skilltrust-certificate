# โจทย์ที่ 3 — ระบบออกและตรวจสอบใบรับรองดิจิทัล
## Blockchain Digital Certificate Verification System (SkillTrust Academy)

ระบบออกใบรับรองดิจิทัลที่บันทึกหลักฐานบน Ethereum Smart Contract เพื่อป้องกันการปลอมแปลงเอกสาร
และให้ผู้ว่าจ้างตรวจสอบคุณวุฒิของผู้สมัครงานได้ทันที

---

## สมาชิกกลุ่ม

| รหัสนักศึกษา | ชื่อ-สกุล |
|---|---|
| 66053541 | จารุกิตติ์ โลบไธสง |
| 66073498 | ฆนาการ ศรีเพ็ญ |
| 66080795 | นรวัฒน์ ดูการดี |
| 66044213 | รัตนพล ศรีโนนยาง |

---

## เทคโนโลยีที่ใช้

| ส่วน | เทคโนโลยี |
|---|---|
| Smart Contract | Solidity ^0.8.20 (Hardhat 2) |
| ทดสอบ | Hardhat Network + Chai (18 test cases) |
| เว็บแอป (DApp) | HTML/JavaScript + ethers.js v5 + MetaMask + QR Code |

## โครงสร้างโปรเจกต์

```
SkillTrust-Certificate/
├── contracts/
│   └── CertificateRegistry.sol   ← Smart Contract หลัก
├── scripts/
│   └── deploy.js                 ← Deploy + เขียน address ให้ frontend
├── test/
│   └── certificate.test.js       ← ทดสอบครบทุกฟังก์ชันและกฎธุรกิจ
├── frontend/
│   └── index.html                ← เว็บแอปเชื่อม MetaMask (เปิดในเบราว์เซอร์ได้เลย)
├── hardhat.config.js
└── package.json
```

## ครอบคลุมฟังก์ชันที่โจทย์ต้องการ

| # | ฟังก์ชันตามโจทย์ | ฟังก์ชันใน Contract | หน้าเว็บ |
|---|---|---|---|
| 1 | ลงทะเบียนหลักสูตร | `createCourse(code, name, details)` — เฉพาะ Admin | แท็บ "หลักสูตร" |
| 2 | ออกใบรับรอง | `issueCertificate(certId, courseCode, holder, hash)` — เฉพาะ Issuer | แท็บ "ออกใบรับรอง" |
| 3 | บันทึก Hash ลง Blockchain | เก็บ `documentHash` (keccak256) พร้อม event `CertificateIssued` | อัตโนมัติตอนออกใบ |
| 4 | ตรวจสอบความถูกต้อง | `verifyCertificate(certId)` และ `findByDocumentHash(hash)` | แท็บ "ตรวจสอบ" + สแกน QR Code |
| 5 | เพิกถอนใบรับรอง | `revokeCertificate(certId, reason)` — เก็บประวัติไว้ ไม่ลบข้อมูล | แท็บ "เพิกถอน" |
| 6 | แสดงประวัติใบรับรอง | `getMyCertificates()` ดึงรายการที่ผูกกับ wallet | แท็บ "ใบรับรองของฉัน" |

## กฎทางธุรกิจสำคัญ — แก้ปัญหาอย่างไร

1. **รหัสใบรับรองห้ามซ้ำ** → contract ตรวจ `require(!certificates[certificateId].exists)`
   (รหัสหลักสูตรก็ซ้ำไม่ได้เช่นกัน) — มีเทสต์ยืนยัน
2. **ผู้ที่ไม่ได้รับอนุญาตห้ามออก/เพิกถอน** → modifier `onlyIssuer` โดย Admin เป็นผู้
   มอบ/ถอนสิทธิ์ผ่าน `addIssuer()` / `removeIssuer()` — มีเทสต์ยืนยัน
3. **ไม่นำข้อมูลส่วนบุคคลขึ้น Public Blockchain** → ชื่อ-นามสกุลผู้รับถูกใช้
   **คำนวณ keccak256 hash ฝั่งเบราว์เซอร์เท่านั้น** สิ่งที่ขึ้น chain มีแค่ hash, wallet address,
   รหัสหลักสูตร และวันที่ — ไม่มีชื่อหรือเลขบัตรประชาชนบน chain เลย
   นอกจากนี้ผู้ตรวจยังอัปโหลดไฟล์ใบรับรองเพื่อเทียบ hash ได้ ถ้าไฟล์ถูกแก้แม้ตัวอักษรเดียว
   hash จะไม่ตรงทันที (กันการแก้ไขชื่อบน PDF เหมือนสถานการณ์ในโจทย์)

## วิธีรันโปรเจกต์

### 1) ติดตั้งและทดสอบ

```bash
npm install
npm run compile   # compile Smart Contract
npm run test      # รัน 18 test cases — ผ่านทั้งหมด
```

### 2) รันระบบบนเครื่อง (Local Blockchain)

```bash
# Terminal 1: เปิด local blockchain
npm run node

# Terminal 2: deploy contract
npm run deploy:local
```

### 3) เปิดเว็บแอป

เปิดไฟล์ `frontend/index.html` ในเบราว์เซอร์ที่มี MetaMask แล้ว:

1. กด **เชื่อมต่อ Wallet**
2. ถ้ายังไม่ได้ตั้งค่า Contract Address → เปิดแท็บ "ใบรับรองของฉัน" →
   ส่วน ⚙️ ตั้งค่า → กรอก address จากขั้นตอน deploy → บันทึก
   (script deploy จะพิมพ์ address ให้ใน terminal)
3. ใน MetaMask เพิ่ม network แบบ custom RPC → URL `http://127.0.0.1:8545`,
   Chain ID `31337` และ import account จาก private key ที่ `npx hardhat node`
   แสดงให้ เพื่อทดสอบบทบาท Admin / Issuer / ผู้รับใบรับรอง

> สำหรับส่งงานบน testnet จริง (Sepolia): ตั้งค่า `PRIVATE_KEY` และ `SEPOLIA_RPC_URL`
> ในไฟล์ `.env` แล้วรัน `npm run deploy:sepolia`

## การทำงานของระบบโดยสรุป

```
ผู้ดูแลระบบ (Admin)
  └─ สร้างหลักสูตร ─────── createCourse()
  └─ มอบสิทธิ์ผู้ออกใบรับรอง ─ addIssuer()

ผู้ออกใบรับรอง (Issuer)
  └─ ออกใบรับรอง: เว็บคำนวณ keccak256(ข้อมูลใบรับรอง) ฝั่งเบราว์เซอร์
      └─ issueCertificate() เก็บ hash ลง Blockchain + สร้าง QR Code ให้ผู้ตรวจ
  └─ เพิกถอนใบรับรองที่ผิดพลาด ─ revokeCertificate() (ประวัติยังอยู่)

ผู้เข้าอบรม (Holder)
  └─ เชื่อม Wallet ดูใบรับรองของตน ─ getMyCertificates()

ผู้ว่าจ้าง / ใครก็ได้ (ไม่ต้องมี Wallet)
  └─ สแกน QR → เปิดหน้าตรวจสอบ → เห็นสถานะ "ถูกต้อง / ถูกเพิกถอน / ไม่พบในระบบ"
  └─ หรืออัปโหลดไฟล์ใบรับรองเพื่อเทียบ hash (กันเอกสารที่ถูกแก้ไข)
```

## ผลการทดสอบ

```
18 passing (2s)
```
ครอบคลุม: การสร้างหลักสูตร, การควบคุมสิทธิ์ (ผู้ไม่ได้รับอนุญาตถูก reject), รหัสซ้ำ,
การออก/ตรวจสอบ/เพิกถอนใบรับรอง, เอกสารที่ถูกแก้ไข hash ไม่ผ่าน,
และการเก็บประวัติหลังเพิกถอน
