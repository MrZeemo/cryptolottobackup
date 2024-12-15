// Setup: npm install alchemy-sdk
import { Network, Alchemy } from "alchemy-sdk";

const settings = {
  apiKey: "x1sb7ERh4AYgxuy75LonH6HJcSMyLfrH",  // Replace with your Alchemy API Key
  network: Network.MATIC_TESTNET,  // Polygon Amoy Testnet
};

const alchemy = new Alchemy(settings);

// Example: Get the latest block number
alchemy.core.getBlockNumber().then(console.log);
