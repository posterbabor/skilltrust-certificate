const { expect } = require("chai");
const { ethers } = require("hardhat");

/**
 * ทดสอบครบทุกฟังก์ชันตามโจทย์ที่ 3 และกฎทางธุรกิจสำคัญ:
 *  - รหัสใบรับรอง/หลักสูตร ห้ามซ้ำ
 *  - ผู้ที่ไม่ได้รับสิทธิ์ ห้ามออก/เพิกถอนใบรับรอง
 *  - เพิกถอนแล้วยังเก็บประวัติ
 *  - เก็บเฉพาะ hash ไม่เก็บข้อมูลส่วนบุคคล
 */
describe("CertificateRegistry", function () {
  let registry;
  let admin, issuer, holder1, holder2, stranger;

  const COURSE_CODE = "AI-101";
  const CERT_ID = "CERT-2026-0001";

  beforeEach(async function () {
    [admin, issuer, holder1, holder2, stranger] = await ethers.getSigners();

    const Factory = await ethers.getContractFactory("CertificateRegistry");
    registry = await Factory.deploy();
    await registry.waitForDeployment();

    await registry.addIssuer(issuer.address);
  });

  // hash เดียวกับที่ frontend ใช้จริง (ข้อมูลส่วนบุคคลถูก hash ฝั่ง client)
  async function makeHash(certId, courseCode, holderAddr) {
    return ethers.solidityPackedKeccak256(
      ["string", "string", "address"],
      [certId, courseCode, holderAddr]
    );
  }

  async function issueSample(certId, holder = holder1) {
    const hash = await makeHash(certId, COURSE_CODE, holder.address);
    await registry.connect(issuer).issueCertificate(certId, COURSE_CODE, holder.address, hash);
    return hash;
  }

  describe("1) Create Training Course", function () {
    it("admin สร้างหลักสูตรได้ และอ่านข้อมูลกลับมาถูกต้อง", async function () {
      await registry.connect(admin).createCourse(COURSE_CODE, "AI Fundamentals", "พื้นฐาน AI 40 ชม.");
      const [name, details, , exists] = await registry.getCourse(COURSE_CODE);
      expect(exists).to.equal(true);
      expect(name).to.equal("AI Fundamentals");
      expect(details).to.equal("พื้นฐาน AI 40 ชม.");

      const list = await registry.getAllCourses();
      expect(list).to.deep.equal([COURSE_CODE]);
    });

    it("คนที่ไม่ใช่ admin สร้างหลักสูตรไม่ได้", async function () {
      await expect(
        registry.connect(stranger).createCourse("HACK-1", "x", "y")
      ).to.be.revertedWith("CertificateRegistry: caller is not admin");
    });

    it("รหัสหลักสูตรซ้ำไม่ได้", async function () {
      await registry.connect(admin).createCourse(COURSE_CODE, "AI", "AI");
      await expect(
        registry.connect(admin).createCourse(COURSE_CODE, "AI ซ้ำ", "ซ้ำ")
      ).to.be.revertedWith("Course code already exists");
    });
  });

  describe("สิทธิ์ผู้ออกใบรับรอง (Issuer management)", function () {
    it("เฉพาะ admin เพิ่ม/ถอนสิทธิ์ issuer ได้", async function () {
      await expect(
        registry.connect(stranger).addIssuer(stranger.address)
      ).to.be.revertedWith("CertificateRegistry: caller is not admin");

      expect(await registry.isIssuer(issuer.address)).to.equal(true);
    });

    it("admin โดยตรงไม่ผ่าน isIssuer แต่ต้องได้รับสิทธิ์ก่อนจึงออกใบรับรองได้", async function () {
      await registry.connect(admin).createCourse(COURSE_CODE, "AI", "AI");
      const hash = await makeHash("X1", COURSE_CODE, holder1.address);
      await expect(
        registry.connect(admin).issueCertificate("X1", COURSE_CODE, holder1.address, hash)
      ).to.be.revertedWith("CertificateRegistry: caller is not authorized issuer");
    });
  });

  describe("2 + 3) Issue Certificate & Store Hash", function () {
    beforeEach(async function () {
      await registry.connect(admin).createCourse(COURSE_CODE, "AI Fundamentals", "40 hours");
    });

    it("issuer ออกใบรับรองได้ และบันทึก hash + วันที่ออก + ผู้รับ", async function () {
      const hash = await issueSample(CERT_ID);

      const [found, valid, courseCode, storedHash, holder, , issuedBy] =
        await registry.verifyCertificate(CERT_ID);

      expect(found).to.equal(true);
      expect(valid).to.equal(true);
      expect(courseCode).to.equal(COURSE_CODE);
      expect(storedHash).to.equal(hash);
      expect(holder).to.equal(holder1.address);
      expect(issuedBy).to.equal(issuer.address);

      expect(await registry.getTotalCertificates()).to.equal(1);
    });

    it("คนที่ไม่ได้รับสิทธิ์ ออกใบรับรองไม่ได้ (กฎธุรกิจ)", async function () {
      const hash = await makeHash("FAKE-1", COURSE_CODE, holder1.address);
      await expect(
        registry.connect(stranger).issueCertificate("FAKE-1", COURSE_CODE, holder1.address, hash)
      ).to.be.revertedWith("CertificateRegistry: caller is not authorized issuer");
    });

    it("รหัสใบรับรองซ้ำไม่ได้ (กฎธุรกิจ)", async function () {
      await issueSample(CERT_ID);
      const hash2 = await makeHash(CERT_ID, "AI-102", holder2.address);
      await expect(
        registry.connect(issuer).issueCertificate(CERT_ID, "AI-102", holder2.address, hash2)
      ).to.be.revertedWith("Certificate ID already exists");
    });

    it("ออกใบรับรองให้หลักสูตรที่ยังไม่มีในระบบไม่ได้", async function () {
      const hash = await makeHash("C2", "NO-COURSE", holder1.address);
      await expect(
        registry.connect(issuer).issueCertificate("C2", "NO-COURSE", holder1.address, hash)
      ).to.be.revertedWith("Course does not exist");
    });
  });

  describe("4) Verify Certificate", function () {
    beforeEach(async function () {
      await registry.connect(admin).createCourse(COURSE_CODE, "AI Fundamentals", "40 hours");
      await issueSample(CERT_ID);
    });

    it("รหัสที่ไม่มีในระบบ ต้องบอกว่า found = false", async function () {
      const [found] = await registry.verifyCertificate("NOT-EXIST");
      expect(found).to.equal(false);
    });

    it("ค้นหาด้วย hash ของเอกสารได้ (findByDocumentHash)", async function () {
      const hash = await makeHash(CERT_ID, COURSE_CODE, holder1.address);
      const [cid, found, valid] = await registry.findByDocumentHash(hash);
      expect(found).to.equal(true);
      expect(valid).to.equal(true);
      expect(cid).to.equal(CERT_ID);
    });

    it("hash ที่ถูกแก้ไข (เอกสารปลอม) ต้องเทียบไม่ผ่าน", async function () {
      const tampered = await makeHash(CERT_ID, COURSE_CODE, holder2.address); // แก้ชื่อ/ข้อมูล
      const [, found] = await registry.findByDocumentHash(tampered);
      expect(found).to.equal(false);
    });
  });

  describe("5) Revoke Certificate", function () {
    beforeEach(async function () {
      await registry.connect(admin).createCourse(COURSE_CODE, "AI Fundamentals", "40 hours");
      await issueSample(CERT_ID);
    });

    it("issuer เพิกถอนได้ สถานะเปลี่ยนเป็น invalid แต่ประวัติยังอยู่", async function () {
      await registry.connect(issuer).revokeCertificate(CERT_ID, "ออกผิดพลาด");

      const [found, valid] = await registry.verifyCertificate(CERT_ID);
      expect(found).to.equal(true);   // ประวัติยังถูกเก็บ
      expect(valid).to.equal(false);  // แต่ใช้งานไม่ได้แล้ว

      expect(await registry.getTotalCertificates()).to.equal(1); // ยังนับรวมอยู่
    });

    it("คนที่ไม่ได้รับสิทธิ์ เพิกถอนไม่ได้ (กฎธุรกิจ)", async function () {
      await expect(
        registry.connect(stranger).revokeCertificate(CERT_ID, "hacked")
      ).to.be.revertedWith("CertificateRegistry: caller is not authorized issuer");
    });

    it("เพิกถอนซ้ำไม่ได้", async function () {
      await registry.connect(issuer).revokeCertificate(CERT_ID, "ครั้งแรก");
      await expect(
        registry.connect(issuer).revokeCertificate(CERT_ID, "ครั้งสอง")
      ).to.be.revertedWith("Already revoked");
    });

    it("เพิกถอนใบรับรองที่ไม่มีอยู่จริงไม่ได้", async function () {
      await expect(
        registry.connect(issuer).revokeCertificate("NOPE", "test")
      ).to.be.revertedWith("Certificate not found");
    });
  });

  describe("6) Certificate Dashboard", function () {
    beforeEach(async function () {
      await registry.connect(admin).createCourse(COURSE_CODE, "AI Fundamentals", "40 hours");
    });

    it("ผู้รับเห็นเฉพาะใบรับรองที่ผูกกับ wallet ตัวเอง", async function () {
      await issueSample("CERT-A", holder1);
      await issueSample("CERT-B", holder1);
      await issueSample("CERT-C", holder2);

      const mine1 = await registry.connect(holder1).getMyCertificates();
      const mine2 = await registry.connect(holder2).getMyCertificates();

      expect(mine1).to.deep.equal(["CERT-A", "CERT-B"]);
      expect(mine2).to.deep.equal(["CERT-C"]);
    });

    it("เพิกถอนแล้ว ใบรับรองยังปรากฏในประวัติของ holder", async function () {
      await issueSample("CERT-A", holder1);
      await registry.connect(issuer).revokeCertificate("CERT-A", "test");

      const mine = await registry.connect(holder1).getMyCertificates();
      expect(mine).to.deep.equal(["CERT-A"]);
    });
  });
});
