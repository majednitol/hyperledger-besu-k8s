const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PrefixRegistry", function () {
  let PrefixRegistry;
  let registry;
  let owner;
  let validator1;
  let nonValidator;

  beforeEach(async function () {
    [owner, validator1, nonValidator] = await ethers.getSigners();
    PrefixRegistry = await ethers.getContractFactory("PrefixRegistry");
    registry = await PrefixRegistry.deploy();
    await registry.waitForDeployment();
    
    // Set validator1 as validator
    await registry.setValidator(validator1.address, true);
  });

  describe("Submissions", function () {
    it("Should allow submitting a pending record and store it", async function () {
      const prefix = "192.0.2.0/24";
      const asn = 65536;
      
      const key = ethers.solidityPackedKeccak256(["string", "uint32"], [prefix, asn]);

      await expect(registry.submitRecord(prefix, asn))
        .to.emit(registry, "RecordSubmitted")
        .withArgs(key, prefix, asn, owner.address);

      const record = await registry.records(key);
      expect(record.prefix).to.equal(prefix);
      expect(record.asn).to.equal(asn);
      expect(record.submittedBy).to.equal(owner.address);
      expect(record.status).to.equal(0); // Status.Pending
    });

    it("Should revert if record already exists", async function () {
      const prefix = "192.0.2.0/24";
      const asn = 65536;
      await registry.submitRecord(prefix, asn);

      // Disable cooldown for testing
      await registry.setCooldownPeriod(0);

      await expect(registry.submitRecord(prefix, asn))
        .to.be.revertedWith("PrefixRegistry: Record already exists");
    });

    it("Should enforce cooldown period on submissions", async function () {
      const prefix1 = "192.0.2.0/24";
      const prefix2 = "198.51.100.0/22";
      const asn = 65536;

      await registry.submitRecord(prefix1, asn);

      // Subsequent submit from same account within 10s cooldown should revert
      await expect(registry.submitRecord(prefix2, asn))
        .to.be.revertedWith("PrefixRegistry: Submission cooldown period active");
    });
  });

  describe("Validation workflow", function () {
    let key;

    beforeEach(async function () {
      const prefix = "192.0.2.0/24";
      const asn = 65536;
      key = ethers.solidityPackedKeccak256(["string", "uint32"], [prefix, asn]);
      await registry.submitRecord(prefix, asn);
    });

    it("Should allow validator to validate a record", async function () {
      await expect(registry.connect(validator1).setStatus(key, 1)) // Status.Validated
        .to.emit(registry, "RecordStatusChanged")
        .withArgs(key, 1, validator1.address);

      const record = await registry.records(key);
      expect(record.status).to.equal(1);
    });

    it("Should revert if non-validator tries to set status", async function () {
      await expect(registry.connect(nonValidator).setStatus(key, 1))
        .to.be.revertedWith("PrefixRegistry: Caller is not an authorized validator");
    });
  });

  describe("Pagination", function () {
    beforeEach(async function () {
      await registry.setCooldownPeriod(0);
      await registry.submitRecord("10.0.0.0/8", 100);
      await registry.submitRecord("20.0.0.0/8", 200);
      await registry.submitRecord("30.0.0.0/8", 300);
    });

    it("Should return correct paginated slices", async function () {
      // Fetch first 2 records
      const [keys1, items1] = await registry.getRecordsPage(0, 2);
      expect(keys1.length).to.equal(2);
      expect(items1.length).to.equal(2);
      expect(items1[0].prefix).to.equal("10.0.0.0/8");
      expect(items1[1].prefix).to.equal("20.0.0.0/8");

      // Fetch subsequent record
      const [keys2, items2] = await registry.getRecordsPage(2, 2);
      expect(keys2.length).to.equal(1);
      expect(items2[0].prefix).to.equal("30.0.0.0/8");
    });

    it("Should return empty lists if offset is out of bounds", async function () {
      const [keys, items] = await registry.getRecordsPage(5, 2);
      expect(keys.length).to.equal(0);
      expect(items.length).to.equal(0);
    });
  });
});
