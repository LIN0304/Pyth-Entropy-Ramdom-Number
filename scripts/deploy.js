const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with", deployer.address);

  const network = await hre.ethers.provider.getNetwork();
  const entropyAddr = process.env.ENTROPY_ADDRESS || "0x0000000000000000000000000000000000000000";
  const providerAddr = process.env.PROVIDER_ADDRESS || deployer.address;

  const Lottery = await hre.ethers.getContractFactory("PythEntropyLottery");
  const lottery = await Lottery.deploy(entropyAddr, providerAddr);
  await lottery.deployed();
  console.log("Lottery deployed at", lottery.address);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
