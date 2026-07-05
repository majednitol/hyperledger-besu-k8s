const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Permissioning", function () {
  let Admin, NodeRules, AccountRules, NodeIngress, AccountIngress;
  let adminContract, nodeRules, accountRules, nodeIngress, accountIngress;
  let owner, admin2, user1;

  beforeEach(async function () {
    [owner, admin2, user1] = await ethers.getSigners();

    Admin = await ethers.getContractFactory("Admin");
    adminContract = await Admin.deploy();
    await adminContract.waitForDeployment();

    NodeRules = await ethers.getContractFactory("NodeRules");
    nodeRules = await NodeRules.deploy(await adminContract.getAddress());
    await nodeRules.waitForDeployment();

    AccountRules = await ethers.getContractFactory("AccountRules");
    accountRules = await AccountRules.deploy(await adminContract.getAddress());
    await accountRules.waitForDeployment();

    NodeIngress = await ethers.getContractFactory("NodeIngress");
    nodeIngress = await NodeIngress.deploy();
    await nodeIngress.waitForDeployment();
    await nodeIngress.setRulesAddress(await nodeRules.getAddress());

    AccountIngress = await ethers.getContractFactory("AccountIngress");
    accountIngress = await AccountIngress.deploy();
    await accountIngress.waitForDeployment();
    await accountIngress.setRulesAddress(await accountRules.getAddress());

    // Add admin2
    await adminContract.addAdmin(admin2.address);
  });

  describe("Admin Administration", function () {
    it("Should confirm admins are set correctly", async function () {
      expect(await adminContract.isAdmin(owner.address)).to.be.true;
      expect(await adminContract.isAdmin(admin2.address)).to.be.true;
      expect(await adminContract.isAdmin(user1.address)).to.be.false;
    });

    it("Should prevent non-admin from adding admin", async function () {
      await expect(adminContract.connect(user1).addAdmin(user1.address))
        .to.be.revertedWith("Admin: Caller is not an authorized administrator");
    });
  });

  describe("Node Rules Allowlist", function () {
    const enode1 = "enode://1234567890abcdef@127.0.0.1:30303";
    const enode2 = "enode://abcdef1234567890@127.0.0.1:30303";

    it("Should allow admins to add and remove enodes", async function () {
      await expect(nodeRules.connect(admin2).addNode(enode1))
        .to.emit(nodeRules, "NodeAdded").withArgs(enode1);
      
      expect(await nodeRules.allowedNodes(enode1)).to.be.true;

      await expect(nodeRules.connect(admin2).removeNode(enode1))
        .to.emit(nodeRules, "NodeRemoved").withArgs(enode1);

      expect(await nodeRules.allowedNodes(enode1)).to.be.false;
    });

    it("Should delegate connection check correctly via Ingress", async function () {
      // By default connection is false
      expect(await nodeIngress.connectionAllowed(enode1, "127.0.0.1", 30303, enode2, "127.0.0.1", 30303))
        .to.be.false;

      // Add both nodes
      await nodeRules.addNode(enode1);
      await nodeRules.addNode(enode2);

      // Now connection is allowed
      expect(await nodeIngress.connectionAllowed(enode1, "127.0.0.1", 30303, enode2, "127.0.0.1", 30303))
        .to.be.true;
    });
  });

  describe("Account Rules Allowlist", function () {
    it("Should allow admins to add and remove transactors", async function () {
      await expect(accountRules.connect(admin2).addAccount(user1.address))
        .to.emit(accountRules, "AccountAdded").withArgs(user1.address);

      expect(await accountRules.allowedAccounts(user1.address)).to.be.true;

      await expect(accountRules.connect(admin2).removeAccount(user1.address))
        .to.emit(accountRules, "AccountRemoved").withArgs(user1.address);

      expect(await accountRules.allowedAccounts(user1.address)).to.be.false;
    });

    it("Should delegate transaction check correctly via Ingress", async function () {
      expect(await accountIngress.transactionAllowed(user1.address, ethers.ZeroAddress, 0, 0, 0, "0x"))
        .to.be.false;

      await accountRules.addAccount(user1.address);

      expect(await accountIngress.transactionAllowed(user1.address, ethers.ZeroAddress, 0, 0, 0, "0x"))
        .to.be.true;
    });
  });
});
