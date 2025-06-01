const hre = require("hardhat");

async function main() {
  const lotteryAddr = process.env.LOTTERY_ADDRESS;
  const Lottery = await hre.ethers.getContractFactory("PythEntropyLottery");
  const lottery = Lottery.attach(lotteryAddr);
  const info = await lottery.getPoolInfo(0);
  console.log("Bronze participants", info.currentParticipants.toString());
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
