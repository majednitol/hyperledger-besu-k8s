const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MedicalRecordRegistry", function () {
  let MedicalRecordRegistry;
  let registry;
  let owner;
  let doctor1;
  let doctor2;
  let patient1;

  beforeEach(async function () {
    [owner, doctor1, doctor2, patient1] = await ethers.getSigners();
    MedicalRecordRegistry = await ethers.getContractFactory("MedicalRecordRegistry");
    registry = await MedicalRecordRegistry.deploy();
    await registry.waitForDeployment();
  });

  describe("Submissions", function () {
    it("Should allow registering a record and store it", async function () {
      const patientId = 101;
      const diagnosisCode = "U07.1";
      const treatmentHash = ethers.keccak256(ethers.toUtf8Bytes("treatment-101"));

      // Initial record: bypasses authorization checks in test mode
      await expect(registry.submitRecord(patientId, diagnosisCode, treatmentHash))
        .to.emit(registry, "RecordRegistered")
        .withArgs(0, patientId, diagnosisCode, owner.address);

      const record = await registry.records(0);
      expect(record.patientId).to.equal(patientId);
      expect(record.diagnosisCode).to.equal(diagnosisCode);
      expect(record.treatmentHash).to.equal(treatmentHash);
      expect(record.doctor).to.equal(owner.address);
      expect(record.active).to.be.true;
    });

    it("Should enforce doctor authorization on subsequent submissions", async function () {
      const patientId = 102;
      const diagnosisCode = "J45.909";
      const treatmentHash = ethers.keccak256(ethers.toUtf8Bytes("treatment-102"));

      // Make first record with owner
      await registry.submitRecord(patientId, diagnosisCode, treatmentHash);

      // Try registering with unauthorized doctor1 (should revert unless authorized or calling from tx.origin)
      // Since it's local hardhat node, connect(doctor1).submitRecord will check authorization
      // Set authorization first
      await registry.setDoctorAuthorization(patientId, doctor1.address, true);

      // Now submit record with doctor1
      await expect(registry.connect(doctor1).submitRecord(patientId, diagnosisCode, treatmentHash))
        .to.emit(registry, "RecordRegistered")
        .withArgs(1, patientId, diagnosisCode, doctor1.address);
    });

    it("Should revert if unauthorized doctor tries to submit after initial setup", async function () {
      const patientId = 103;
      const diagnosisCode = "I10";
      const treatmentHash = ethers.keccak256(ethers.toUtf8Bytes("treatment-103"));

      // Deployer/owner registers first record to increase recordCount > 0
      await registry.submitRecord(patientId, diagnosisCode, treatmentHash);

      // Now doctor2 is unauthorized, connecting should revert because doctor2 is not tx.origin (hardhat signer)
      // Wait, in Hardhat connect(doctor2) will make doctor2 the msg.sender and tx.origin will still be doctor2!
      // So msg.sender == doctor2 and tx.origin == doctor2.
      // Therefore, it will revert because authorizedDoctors[patientId][doctor2] is false!
      await expect(registry.connect(doctor2).submitRecord(patientId, diagnosisCode, treatmentHash))
        .to.be.revertedWith("Doctor is not authorized for this patient");
    });
  });

  describe("Pagination", function () {
    beforeEach(async function () {
      const hash1 = ethers.keccak256(ethers.toUtf8Bytes("treatment-1"));
      const hash2 = ethers.keccak256(ethers.toUtf8Bytes("treatment-2"));
      const hash3 = ethers.keccak256(ethers.toUtf8Bytes("treatment-3"));

      await registry.submitRecord(101, "U07.1", hash1);
      await registry.submitRecord(102, "J45.909", hash2);
      await registry.submitRecord(103, "I10", hash3);
    });

    it("Should return correct paginated slices", async function () {
      // Fetch first 2 records
      const [keys1, items1] = await registry.getRecordsPage(0, 2);
      expect(keys1.length).to.equal(2);
      expect(items1.length).to.equal(2);
      expect(items1[0].patientId).to.equal(101);
      expect(items1[1].patientId).to.equal(102);

      // Fetch subsequent record
      const [keys2, items2] = await registry.getRecordsPage(2, 2);
      expect(keys2.length).to.equal(1);
      expect(items2[0].patientId).to.equal(103);
    });

    it("Should return empty lists if offset is out of bounds", async function () {
      const [keys, items] = await registry.getRecordsPage(5, 2);
      expect(keys.length).to.equal(0);
      expect(items.length).to.equal(0);
    });
  });
});
