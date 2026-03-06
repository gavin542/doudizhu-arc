// Deploy DoudizhuGame contract to Arc Testnet
// Usage: node scripts/deploy.mjs

import { ethers } from "ethers";
import { readFileSync } from "fs";
import { execSync } from "child_process";
import "dotenv/config";

const RPC_URL = process.env.ARC_TESTNET_RPC_URL || "https://rpc.testnet.arc.network";
const PRIVATE_KEY = process.env.DEPLOY_PRIVATE_KEY;

if (!PRIVATE_KEY) {
  console.error("Please set DEPLOY_PRIVATE_KEY in .env");
  process.exit(1);
}

// Method 1: Compile with Foundry solc
async function compileWithFoundry() {
  console.log("Compiling contract...");
  try {
    execSync("forge build --root . 2>/dev/null || solc --abi --bin --overwrite -o build contracts/DoudizhuGame.sol", {
      stdio: "pipe",
    });
  } catch {
    console.log("Foundry/solc not found, using pre-compiled ABI...");
    return null;
  }
}

// Contract ABI (manually maintained, synced with .sol)
const CONTRACT_ABI = [
  "function createGame() external payable returns (uint256)",
  "function joinGame(uint256 gameId) external payable",
  "function settleGame(uint256 gameId, address winner) external",
  "function cancelGame(uint256 gameId) external",
  "function claimTimeout(uint256 gameId) external",
  "function TIMEOUT() external view returns (uint256)",
  "function getPlayerStats(address player) external view returns (uint256 wins, uint256 losses, uint256 totalEarnings, uint256 totalGames)",
  "function getTopPlayers() external view returns (address[] addresses, uint256[] wins, uint256[] earnings)",
  "function getGame(uint256 gameId) external view returns (address host, uint8 playerCount, uint256 betAmount, bool settled, address winner)",
  "function nextGameId() external view returns (uint256)",
  "function BET_AMOUNT() external view returns (uint256)",
  "event GameCreated(uint256 indexed gameId, address indexed host, uint256 betAmount)",
  "event PlayerJoined(uint256 indexed gameId, address indexed player, uint8 slot)",
  "event GameSettled(uint256 indexed gameId, address indexed winner, uint256 prize)",
  "event GameCancelled(uint256 indexed gameId, address indexed host, uint256 refundTotal)",
];

// Contract bytecode - needs forge build or solc compilation
// If you have Foundry, run: forge build
// Then read bytecode from out/DoudizhuGame.sol/DoudizhuGame.json
async function deploy() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

  console.log(`Deploy account: ${wallet.address}`);
  const balance = await provider.getBalance(wallet.address);
  console.log(`Account balance: ${ethers.formatEther(balance)} USDC`);

  // Try reading bytecode from Foundry output
  let bytecode;
  try {
    const artifact = JSON.parse(
      readFileSync("out/DoudizhuGame.sol/DoudizhuGame.json", "utf8")
    );
    bytecode = artifact.bytecode.object || artifact.bytecode;
    console.log("Read bytecode from Foundry build output");
  } catch {
    // Try solc output
    try {
      bytecode = "0x" + readFileSync("build/DoudizhuGame.bin", "utf8").trim();
      console.log("Read bytecode from solc build output");
    } catch {
      console.error(
        "Build output not found. Please run first:\n" +
        "  forge build           (if you have Foundry)\n" +
        "  or solc --abi --bin --overwrite -o build contracts/DoudizhuGame.sol"
      );
      process.exit(1);
    }
  }

  console.log("Deploying contract...");
  const factory = new ethers.ContractFactory(CONTRACT_ABI, bytecode, wallet);
  const contract = await factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log(`\nContract deployed!`);
  console.log(`Address: ${address}`);
  console.log(`\nPlease add contract address to .env:`);
  console.log(`CONTRACT_ADDRESS=${address}`);
  console.log(`\nAnd update CONTRACT_ADDRESS constant in index.html`);
}

deploy().catch(console.error);
