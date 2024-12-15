const hre = require("hardhat");

async function main() {
  const Lottery = await hre.ethers.getContractFactory("Lottery");
  
  // Polygon Amoy testnet addresses
  const vrfCoordinator = "0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed";
  const subscriptionId = "YOUR_SUBSCRIPTION_ID"; // Replace with your Chainlink VRF subscription ID
  const keyHash = "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f";
  const callbackGasLimit = 2500000;
  const tetherAddress = "0xA02f6adc7926efeBBd59Fd43A84f4E0c0c91e832"; // Amoy USDT address

  const lottery = await Lottery.deploy(
    vrfCoordinator,
    subscriptionId,
    keyHash,
    callbackGasLimit,
    tetherAddress
  );

  await lottery.deployed();

  console.log("Lottery deployed to:", lottery.address);

  // Initialize the contract
  await lottery.initialize();
  console.log("Lottery initialized");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });