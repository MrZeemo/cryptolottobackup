const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Lottery", function () {
  let Lottery, lottery, MockVRFCoordinator, mockVRFCoordinator, MockUSDT, mockUSDT, owner, addr1, addr2;
  const subscriptionId = 1234n;
  const keyHash = "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f";
  const callbackGasLimit = 200000n;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    // Deploy mock VRF Coordinator
    MockVRFCoordinator = await ethers.getContractFactory("MockVRFCoordinatorV2");
    mockVRFCoordinator = await MockVRFCoordinator.deploy();

    // Deploy mock USDT
    MockUSDT = await ethers.getContractFactory("MockUSDT");
    mockUSDT = await MockUSDT.deploy();

    // Deploy Lottery contract
    Lottery = await ethers.getContractFactory("Lottery");
    lottery = await Lottery.deploy(
      await mockVRFCoordinator.getAddress(),
      subscriptionId,
      keyHash,
      callbackGasLimit,
      await mockUSDT.getAddress()
    );

    // Initialize the lottery contract
    await lottery.initialize();

    // Approve USDT for lottery contract
    const maxApproval = ethers.MaxUint256;
    await mockUSDT.connect(owner).approve(await lottery.getAddress(), maxApproval);
    await mockUSDT.connect(addr1).approve(await lottery.getAddress(), maxApproval);
    await mockUSDT.connect(addr2).approve(await lottery.getAddress(), maxApproval);

    // Transfer some USDT to test addresses
    const amount = ethers.parseUnits("1000", 6); // 1000 USDT
    await mockUSDT.transfer(addr1.address, amount);
    await mockUSDT.transfer(addr2.address, amount);
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await lottery.owner()).to.equal(owner.address);
    });

    it("Should set the correct USDT address", async function () {
      expect(await lottery.tether()).to.equal(await mockUSDT.getAddress());
    });
  });

  describe("Create Lottery", function () {
    it("Should create a new lottery", async function () {
      await lottery.createLottery(ethers.parseUnits("10", 6), ethers.parseUnits("1000", 6));
      const lotteryInfo = await lottery.lotteries(1);
      expect(lotteryInfo.entryFee).to.equal(ethers.parseUnits("10", 6));
      expect(lotteryInfo.targetPrizePool).to.equal(ethers.parseUnits("1000", 6));
    });

    it("Should fail to create a lottery with zero entry fee", async function () {
      await expect(lottery.createLottery(0, ethers.parseUnits("1000", 6)))
        .to.be.revertedWith("Entry fee must be greater than zero");
    });

    it("Should fail to create a lottery with zero target prize pool", async function () {
      await expect(lottery.createLottery(ethers.parseUnits("10", 6), 0))
        .to.be.revertedWith("Target prize pool must be greater than zero");
    });

    it("Should only allow owner to create a lottery", async function () {
      await expect(lottery.connect(addr1).createLottery(ethers.parseUnits("10", 6), ethers.parseUnits("1000", 6)))
        .to.be.revertedWithCustomError(lottery, "OwnableUnauthorizedAccount")
        .withArgs(addr1.address);
    });
  });

  describe("Enter Lottery", function () {
    beforeEach(async function () {
      await lottery.createLottery(ethers.parseUnits("10", 6), ethers.parseUnits("1000", 6));
    });

    it("Should allow a user to enter the lottery", async function () {
      await lottery.connect(addr1).enterLottery(1, 1);
      const lotteryInfo = await lottery.lotteries(1);
      expect(lotteryInfo.totalEntries).to.equal(1);
    });

    it("Should fail to enter a non-existent lottery", async function () {
      await expect(lottery.connect(addr1).enterLottery(2, 1))
        .to.be.revertedWith("Invalid lottery ID");
    });

    it("Should fail to enter with zero entries", async function () {
      await expect(lottery.connect(addr1).enterLottery(1, 0))
        .to.be.revertedWith("Must enter at least one entry");
    });

    it("Should update total entries and prize pool", async function () {
      await lottery.connect(addr1).enterLottery(1, 2);
      const lotteryInfo = await lottery.lotteries(1);
      expect(lotteryInfo.totalEntries).to.equal(2);
      expect(lotteryInfo.totalPrizePool).to.equal(ethers.parseUnits("20", 6));
    });

    it("Should emit ThresholdMet event when threshold is reached", async function () {
      const threshold = ethers.parseUnits("330", 6); // 33% of 1000
      const tx = await lottery.connect(addr1).enterLottery(1, 33);
      const receipt = await tx.wait();
      
      const event = receipt.logs.find(
        log => log.fragment && log.fragment.name === 'ThresholdMet'
      );
      
      expect(event).to.not.be.undefined;
      expect(event.args[0]).to.equal(1n); // lotteryId
      expect(event.args[1]).to.equal(threshold); // thresholdAmount
      
      // Get the block timestamp from the actual transaction
      const block = await ethers.provider.getBlock(receipt.blockNumber);
      const expectedDeadline = BigInt(block.timestamp) + 24n * 60n * 60n;
      expect(event.args[2]).to.equal(expectedDeadline); // deadlineTime
    });
  });

  describe("Request Random Words", function () {
    beforeEach(async function () {
      await lottery.createLottery(ethers.parseUnits("10", 6), ethers.parseUnits("1000", 6));
      await lottery.connect(addr1).enterLottery(1, 33); // Ensure threshold is met
    });

    it("Should only allow owner to request random words", async function () {
      await expect(lottery.connect(addr1).requestRandomWords(1))
        .to.be.revertedWithCustomError(lottery, "OwnableUnauthorizedAccount")
        .withArgs(addr1.address);
    });

    it("Should fail if lottery has no entries", async function () {
      await lottery.createLottery(ethers.parseUnits("10", 6), ethers.parseUnits("1000", 6));
      await expect(lottery.requestRandomWords(2))
        .to.be.revertedWith("No entries in the lottery");
    });

    it("Should fail if threshold is not met", async function () {
      await lottery.createLottery(ethers.parseUnits("10", 6), ethers.parseUnits("1000", 6));
      await lottery.connect(addr1).enterLottery(2, 1);
      await expect(lottery.requestRandomWords(2))
        .to.be.revertedWith("Threshold not met");
    });

    it("Should end the lottery when requesting random words", async function () {
      await ethers.provider.send("evm_increaseTime", [24 * 60 * 60]);
      await lottery.requestRandomWords(1);
      const lotteryInfo = await lottery.lotteries(1);
      expect(lotteryInfo.lotteryEnded).to.be.true;
    });
  });

  describe("Claim Prize", function () {
    beforeEach(async function () {
      await lottery.createLottery(ethers.parseUnits("10", 6), ethers.parseUnits("1000", 6));
      await lottery.connect(addr1).enterLottery(1, 33);
      await ethers.provider.send("evm_increaseTime", [24 * 60 * 60]);
      await lottery.requestRandomWords(1);
      
      // Manually distribute prizes
      const winners = [addr1.address];
      const amounts = [ethers.parseUnits("100", 6)];
      await lottery.distributePrizesManually(1, winners, amounts);
    });

    it("Should allow winner to claim prize", async function () {
      const initialBalance = await mockUSDT.balanceOf(addr1.address);
      await lottery.connect(addr1).claimPrize(1);
      const finalBalance = await mockUSDT.balanceOf(addr1.address);
      expect(finalBalance - initialBalance).to.equal(ethers.parseUnits("100", 6));
    });

    it("Should fail if prizes are not distributed", async function () {
      await lottery.createLottery(ethers.parseUnits("10", 6), ethers.parseUnits("1000", 6));
      await expect(lottery.connect(addr1).claimPrize(2))
        .to.be.revertedWith("Prizes not yet distributed");
    });

    it("Should fail if user has no prize to claim", async function () {
      await expect(lottery.connect(addr2).claimPrize(1))
        .to.be.revertedWith("No prize to claim");
    });

    it("Should not allow claiming prize twice", async function () {
      await lottery.connect(addr1).claimPrize(1);
      await expect(lottery.connect(addr1).claimPrize(1))
        .to.be.revertedWith("No prize to claim");
    });
  });

  describe("Pause and Unpause", function () {
    it("Should allow owner to pause the contract", async function () {
      await lottery.pause();
      expect(await lottery.paused()).to.be.true;
    });

    it("Should allow owner to unpause the contract", async function () {
      await lottery.pause();
      await lottery.unpause();
      expect(await lottery.paused()).to.be.false;
    });

    it("Should not allow non-owner to pause", async function () {
      await expect(lottery.connect(addr1).pause())
        .to.be.revertedWithCustomError(lottery, "OwnableUnauthorizedAccount")
        .withArgs(addr1.address);
    });

    it("Should not allow entering lottery when paused", async function () {
      await lottery.createLottery(ethers.parseUnits("10", 6), ethers.parseUnits("1000", 6));
      await lottery.pause();
      await expect(lottery.connect(addr1).enterLottery(1, 1))
        .to.be.revertedWithCustomError(lottery, "EnforcedPause");
    });
  });
});