const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PythEntropyLottery", function () {
  let lottery, mockEntropy, owner, user;

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();
    const MockEntropy = await ethers.getContractFactory("MockEntropy");
    mockEntropy = await MockEntropy.deploy();
    await mockEntropy.deployed();
    const Lottery = await ethers.getContractFactory("PythEntropyLottery");
    lottery = await Lottery.deploy(mockEntropy.address, owner.address);
    await lottery.deployed();
    await mockEntropy.setAuthorizedCallback(lottery.address);
  });

  it("allows entry into bronze pool", async function () {
    await lottery.connect(user).enterLottery(0, ethers.constants.AddressZero, { value: ethers.utils.parseEther("0.01") });
    const info = await lottery.getPoolInfo(0);
    expect(info.currentParticipants).to.equal(1);
  });
});
