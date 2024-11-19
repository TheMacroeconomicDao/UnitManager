const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("GybernatyUnitManager", function () {
  let gybernatyManager;
  let gbrToken;
  let owner;
  let gybernaty;
  let user;
  let user2;

  const GBR_TOKEN_AMOUNT = ethers.parseUnits("1000000000000", "wei");
  const BNB_AMOUNT = ethers.parseEther("1000");

  beforeEach(async function () {
    [owner, gybernaty, user, user2] = await ethers.getSigners();

    // Deploy mock GBR token
    const MockGBRToken = await ethers.getContractFactory("MockGBRToken");
    gbrToken = await MockGBRToken.deploy();

    // Deploy GybernatyUnitManager
    const GybernatyUnitManager = await ethers.getContractFactory("GybernatyUnitManager");
    gybernatyManager = await GybernatyUnitManager.deploy(gbrToken.address);

    // Mint tokens for testing
    await gbrToken.mint(gybernaty.address, GBR_TOKEN_AMOUNT);
    await gbrToken.connect(gybernaty).approve(gybernatyManager.address, GBR_TOKEN_AMOUNT);
  });

  describe("Joining as Gybernaty", function () {
    it("Should allow joining with GBR tokens", async function () {
      await expect(gybernatyManager.connect(gybernaty).joinGybernaty())
        .to.emit(gybernatyManager, "GybernatyJoined")
        .withArgs(gybernaty.address, GBR_TOKEN_AMOUNT);
    });

    it("Should allow joining with BNB", async function () {
      await expect(gybernatyManager.connect(user).joinGybernaty({ value: BNB_AMOUNT }))
        .to.emit(gybernatyManager, "GybernatyJoined")
        .withArgs(user.address, BNB_AMOUNT);
    });

    it("Should revert if insufficient payment", async function () {
      await expect(gybernatyManager.connect(user).joinGybernaty({ value: 0 }))
        .to.be.revertedWithCustomError(gybernatyManager, "InsufficientPayment");
    });
  });

  describe("User Management", function () {
    beforeEach(async function () {
      await gybernatyManager.connect(gybernaty).joinGybernaty();
    });

    it("Should create a new user", async function () {
      await expect(gybernatyManager.connect(gybernaty).createUser(
        user.address,
        1,
        "Test User",
        "https://example.com"
      )).to.emit(gybernatyManager, "UserCreated")
        .withArgs(user.address, "Test User", 1);
    });

    it("Should mark user for level up", async function () {
      await gybernatyManager.connect(gybernaty).createUser(
        user.address,
        1,
        "Test User",
        "https://example.com"
      );

      await expect(gybernatyManager.connect(user).markForLevelUp())
        .to.emit(gybernatyManager, "UserMarkedUp")
        .withArgs(user.address, 1);
    });

    it("Should execute level up", async function () {
      await gybernatyManager.connect(gybernaty).createUser(
        user.address,
        1,
        "Test User",
        "https://example.com"
      );
      await gybernatyManager.connect(user).markForLevelUp();

      await expect(gybernatyManager.connect(gybernaty).executeUserLevelChange(user.address, true))
        .to.emit(gybernatyManager, "UserLevelChanged")
        .withArgs(user.address, 1, 2);
    });
  });

  describe("Token Withdrawals", function () {
    beforeEach(async function () {
      await gybernatyManager.connect(gybernaty).joinGybernaty();
      await gybernatyManager.connect(gybernaty).createUser(
        user.address,
        1,
        "Test User",
        "https://example.com"
      );
      await gbrToken.mint(gybernatyManager.address, ethers.parseUnits("10000000000000", "wei"));
    });

    it("Should allow token withdrawal within limits", async function () {
      const withdrawAmount = ethers.parseUnits("1000000000000", "wei");
      await expect(gybernatyManager.connect(user).withdrawTokens(withdrawAmount))
        .to.emit(gybernatyManager, "TokensWithdrawn")
        .withArgs(user.address, withdrawAmount);
    });

    it("Should revert on exceeding monthly withdrawal limit", async function () {
      const withdrawAmount = ethers.parseUnits("1000000000000", "wei");
      await gybernatyManager.connect(user).withdrawTokens(withdrawAmount);
      await gybernatyManager.connect(user).withdrawTokens(withdrawAmount);
      
      await expect(gybernatyManager.connect(user).withdrawTokens(withdrawAmount))
        .to.be.revertedWithCustomError(gybernatyManager, "WithdrawalLimitExceeded");
    });
  });

  describe("Admin Functions", function () {
    it("Should allow admin to pause contract", async function () {
      await expect(gybernatyManager.connect(owner).pause())
        .to.emit(gybernatyManager, "Paused")
        .withArgs(owner.address);
    });

    it("Should allow admin to unpause contract", async function () {
      await gybernatyManager.connect(owner).pause();
      await expect(gybernatyManager.connect(owner).unpause())
        .to.emit(gybernatyManager, "Unpaused")
        .withArgs(owner.address);
    });
  });
});