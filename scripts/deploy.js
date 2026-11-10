const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const CertificateRegistry = await hre.ethers.getContractFactory("CertificateRegistry");
  const registry = await CertificateRegistry.deploy();
  await registry.waitForDeployment();

  const address = await registry.getAddress();
  console.log("CertificateRegistry deployed to:", address);

  // Deployer (admin) ตั้งตัวเองเป็น issuer คนแรกเพื่อความสะดวกในการทดลอง
  // (admin สร้างหลักสูตรได้ แต่การออกใบรับรองต้องเป็น issuer)
  const tx = await registry.addIssuer(deployer.address);
  await tx.wait();
  console.log("Deployer added as issuer:", deployer.address);

  // เขียน address ลง frontend เพื่อให้เว็บแอปใช้งานได้ทันที
  const fs = require("fs");
  const cfgPath = __dirname + "/../frontend/deployed.json";
  fs.writeFileSync(cfgPath, JSON.stringify({ address, network: hre.network.name }, null, 2));
  console.log("Saved to", cfgPath);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
