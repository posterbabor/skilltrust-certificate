// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CertificateRegistry
 * @notice ระบบออกและตรวจสอบใบรับรองดิจิทัล บน Ethereum Smart Contract
 *         สำหรับ SkillTrust Academy
 *
 * หลักการออกแบบตามโจทย์:
 *  1. ลงทะเบียนหลักสูตร      -> createCourse()
 *  2. ออกใบรับรอง           -> issueCertificate() (เฉพาะผู้ได้รับสิทธิ์ onlyIssuer)
 *  3. บันทึกหลักฐานบน Chain -> เก็บเฉพาะ keccak256 hash ของเอกสาร ไม่เก็บข้อมูลส่วนบุคคล
 *  4. ตรวจสอบความถูกต้อง    -> verifyCertificate() (read-only, ใช้กับ QR Code ได้)
 *  5. เพิกถอนใบรับรอง       -> revokeCertificate() (เก็บประวัติไว้ ไม่ลบข้อมูล)
 *  6. แสดงประวัติใบรับรอง   -> getMyCertificates() / getHolderCertificates()
 *
 * กฎทางธุรกิจ:
 *  - รหัสใบรับรองต้องไม่ซ้ำกัน (unique certificateId)
 *  - ห้ามผู้ที่ไม่ได้รับอนุญาตออก/เพิกถอนใบรับรอง (onlyIssuer / onlyAdmin)
 *  - ไม่นำข้อมูลส่วนบุคคลขึ้น Public Blockchain โดยตรง (เก็บเฉพาะ hash)
 */
contract CertificateRegistry {
    // ---------------------------------------------------------------------
    // Roles
    // ---------------------------------------------------------------------
    address public admin;

    mapping(address => bool) public isIssuer;
    address[] private issuerList;

    // ---------------------------------------------------------------------
    // Structures
    // ---------------------------------------------------------------------
    struct Course {
        string code;        // รหัสหลักสูตร เช่น "AI-101"
        string name;        // ชื่อหลักสูตร
        string details;     // รายละเอียดการอบรม
        uint256 createdAt;  // วันที่สร้างหลักสูตร
        bool exists;
    }

    struct Certificate {
        string certificateId;   // รหัสอ้างอิงใบรับรอง (unique)
        string courseCode;      // รหัสหลักสูตรที่เกี่ยวข้อง
        bytes32 documentHash;   // hash ของข้อมูลใบรับรอง (ไม่เก็บข้อมูลจริง)
        address holder;         // wallet ของผู้รับใบรับรอง
        uint256 issuedAt;       // วันที่ออก (block timestamp)
        address issuedBy;       // ผู้ออกใบรับรอง
        bool valid;             // false = ถูกเพิกถอน
        bool exists;
    }

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------
    mapping(string => Course) private courses;
    string[] private courseList;

    mapping(string => Certificate) private certificates;   // key = certificateId
    string[] private certificateList;
    mapping(address => string[]) private holderCertificates; // wallet -> รายการรหัสใบรับรอง
    mapping(bytes32 => string) private hashToCertificateId; // ค้นกลับจาก hash ได้

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    event CourseCreated(string indexed courseCode, string name, address indexed createdBy);
    event IssuerAdded(address indexed issuer, address indexed addedBy);
    event IssuerRemoved(address indexed issuer, address indexed removedBy);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    event CertificateIssued(
        string indexed certificateId,
        string indexed courseCode,
        address indexed holder,
        bytes32 documentHash,
        address issuedBy,
        uint256 issuedAt
    );
    event CertificateRevoked(string indexed certificateId, address indexed revokedBy, uint256 revokedAt, string reason);

    // ---------------------------------------------------------------------
    // Constructor & Modifiers
    // ---------------------------------------------------------------------
    constructor() {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "CertificateRegistry: caller is not admin");
        _;
    }

    modifier onlyIssuer() {
        require(isIssuer[msg.sender], "CertificateRegistry: caller is not authorized issuer");
        _;
    }

    // ---------------------------------------------------------------------
    // 1) ลงทะเบียนหลักสูตร (Create Training Course) - ผู้ดูแลระบบเท่านั้น
    // ---------------------------------------------------------------------
    function createCourse(
        string calldata code,
        string calldata name,
        string calldata details
    ) external onlyAdmin {
        bytes32 codeHash = keccak256(bytes(code));
        require(codeHash != bytes32(0), "Course code is required");
        require(!courses[code].exists, "Course code already exists");

        courses[code] = Course({
            code: code,
            name: name,
            details: details,
            createdAt: block.timestamp,
            exists: true
        });
        courseList.push(code);

        emit CourseCreated(code, name, msg.sender);
    }

    function getCourse(string calldata code)
        external view
        returns (string memory name, string memory details, uint256 createdAt, bool exists)
    {
        Course memory c = courses[code];
        return (c.name, c.details, c.createdAt, c.exists);
    }

    function getAllCourses() external view returns (string[] memory) {
        return courseList;
    }

    // ---------------------------------------------------------------------
    // การจัดการสิทธิ์ (ผู้ดูแลระบบเพิ่ม/ถอนสิทธิ์ผู้ออกใบรับรอง)
    // ---------------------------------------------------------------------
    function addIssuer(address account) external onlyAdmin {
        require(account != address(0), "Zero address");
        require(!isIssuer[account], "Already an issuer");

        isIssuer[account] = true;
        issuerList.push(account);

        emit IssuerAdded(account, msg.sender);
    }

    function removeIssuer(address account) external onlyAdmin {
        require(isIssuer[account], "Not an issuer");
        isIssuer[account] = false;

        emit IssuerRemoved(account, msg.sender);
    }

    function getIssuers() external view returns (address[] memory) {
        return issuerList;
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Zero address");
        address previous = admin;
        admin = newAdmin;

        emit AdminTransferred(previous, newAdmin);
    }

    // ---------------------------------------------------------------------
    // 2 + 3) ออกใบรับรอง + บันทึก Hash ลง Blockchain (เฉพาะผู้ได้รับสิทธิ์)
    // ---------------------------------------------------------------------
    /**
     * @notice ออกใบรับรองพร้อมรหัสอ้างอิง โดยเก็บเฉพาะ hash ของข้อมูล
     *         ข้อมูลส่วนบุคคล (ชื่อ-นามสกุล, เลขบัตร ฯลฯ) ต้องไม่ถูกส่งเข้าฟังก์ชันนี้
     *         ให้เว็บแอปคำนวณ hash จากข้อมูลจริงฝั่ง client ก่อนเสมอ
     * @param certificateId รหัสอ้างอิงใบรับรอง ต้องไม่ซ้ำกัน
     * @param courseCode     รหัสหลักสูตรที่ต้องลงทะเบียนไว้แล้ว
     * @param holder         wallet address ของผู้รับใบรับรอง
     * @param documentHash   keccak256 ของข้อมูลใบรับรอง (คำนวณฝั่ง client)
     */
    function issueCertificate(
        string calldata certificateId,
        string calldata courseCode,
        address holder,
        bytes32 documentHash
    ) external onlyIssuer {
        require(bytes(certificateId).length > 0, "Certificate ID is required");
        require(!certificates[certificateId].exists, "Certificate ID already exists"); // กฎ: รหัสห้ามซ้ำ
        require(courses[courseCode].exists, "Course does not exist");
        require(holder != address(0), "Holder is required");
        require(documentHash != bytes32(0), "Document hash is required");

        certificates[certificateId] = Certificate({
            certificateId: certificateId,
            courseCode: courseCode,
            documentHash: documentHash,
            holder: holder,
            issuedAt: block.timestamp,
            issuedBy: msg.sender,
            valid: true,
            exists: true
        });

        certificateList.push(certificateId);
        holderCertificates[holder].push(certificateId);
        hashToCertificateId[documentHash] = certificateId;

        emit CertificateIssued(certificateId, courseCode, holder, documentHash, msg.sender, block.timestamp);
    }

    // ---------------------------------------------------------------------
    // 4) ตรวจสอบความถูกต้อง (Verify Certificate)
    // ---------------------------------------------------------------------
    /**
     * @notice ตรวจสอบสถานะใบรับรองด้วยรหัสอ้างอิง (ใช้กับ QR Code ได้)
     * @return found      มีใบรับรองนี้ในระบบหรือไม่
     * @return valid      true = ยังมีผลใช้งาน / false = ถูกเพิกถอน
     * @return courseCode รหัสหลักสูตร
     * @return documentHash hash อ้างอิง (เอาไปเทียบกับ hash ของไฟล์ที่ส่งมาตรวจ)
     * @return holder     wallet ของผู้รับ
     * @return issuedAt   วันที่ออก
     * @return issuedBy   ผู้ออก
     */
    function verifyCertificate(string calldata certificateId)
        external view
        returns (
            bool found,
            bool valid,
            string memory courseCode,
            bytes32 documentHash,
            address holder,
            uint256 issuedAt,
            address issuedBy
        )
    {
        Certificate memory cert = certificates[certificateId];
        if (!cert.exists) {
            return (false, false, "", bytes32(0), address(0), 0, address(0));
        }
        return (true, cert.valid, cert.courseCode, cert.documentHash, cert.holder, cert.issuedAt, cert.issuedBy);
    }

    /// @notice ค้นหาใบรับรองจาก hash ของเอกสาร (กรณีมีเฉพาะไฟล์ใบรับรอง)
    function findByDocumentHash(bytes32 documentHash)
        external view
        returns (string memory certificateId, bool found, bool valid)
    {
        string memory cid = hashToCertificateId[documentHash];
        if (bytes(cid).length == 0) {
            return ("", false, false);
        }
        return (cid, true, certificates[cid].valid);
    }

    // ---------------------------------------------------------------------
    // 5) เพิกถอนใบรับรอง (Revoke Certificate) - เก็บประวัติไว้
    // ---------------------------------------------------------------------
    function revokeCertificate(string calldata certificateId, string calldata reason)
        external onlyIssuer
    {
        Certificate storage cert = certificates[certificateId];
        require(cert.exists, "Certificate not found");
        require(cert.valid, "Already revoked");

        cert.valid = false;

        emit CertificateRevoked(certificateId, msg.sender, block.timestamp, reason);
    }

    // ---------------------------------------------------------------------
    // 6) ประวัติใบรับรอง (Certificate Dashboard)
    // ---------------------------------------------------------------------
    /// @notice รายการใบรับรองที่ผูกกับ wallet ของผู้เรียก (ใช้ทำ Dashboard)
    function getMyCertificates() external view returns (string[] memory) {
        return holderCertificates[msg.sender];
    }

    /// @notice รายการใบรับรองของ address ใด ๆ (ใช้ตรวจโดยผู้ดูแล)
    function getHolderCertificates(address holder) external view returns (string[] memory) {
        return holderCertificates[holder];
    }

    /// @notice จำนวนใบรับรองทั้งหมดที่ระบบเคยออก (รวมที่ถูกเพิกถอน - ประวัติถูกเก็บไว้)
    function getTotalCertificates() external view returns (uint256) {
        return certificateList.length;
    }

    /// @notice รายการรหัสใบรับรองทั้งหมด (ประวัติถูกเก็บไว้แม้เพิกถอนแล้ว)
    function getAllCertificates() external view returns (string[] memory) {
        return certificateList;
    }
}
