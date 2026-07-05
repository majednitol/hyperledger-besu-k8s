"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const ethers_1 = require("ethers");
const dotenv = __importStar(require("dotenv"));
dotenv.config();
const PRIVATE_RPC_URL = process.env.PRIVATE_RPC_URL || "http://127.0.0.1:8545";
const PUBLIC_RPC_URL = process.env.PUBLIC_RPC_URL || "http://127.0.0.1:8545";
const PRIVATE_REGISTRY_ADDRESS = process.env.PRIVATE_REGISTRY_ADDRESS;
const PUBLIC_ANCHOR_ADDRESS = process.env.PUBLIC_ANCHOR_ADDRESS;
const RELAYER_KEY = process.env.RELAYER_KEY;
const PRIVATE_REGISTRY_ABI = [
    "function recordCount() external view returns (uint256)",
    "function getRecordsPage(uint256 offset, uint256 limit) external view returns (bytes32[] keys, tuple(string prefix, uint32 asn, address submittedBy, uint8 status, uint256 submittedAt, uint256 updatedAt)[] items)"
];
const PUBLIC_ANCHOR_ABI = [
    "function submitAnchor(bytes32 merkleRoot, uint256 privateBlockNumber) external",
    "function latest() external view returns (tuple(bytes32 merkleRoot, uint256 privateBlockNumber, uint256 timestamp))"
];
// Helper to compute a standard binary Merkle tree root from leaves
function computeMerkleRoot(leaves) {
    if (leaves.length === 0) {
        return ethers_1.ethers.ZeroHash;
    }
    let level = [...leaves];
    while (level.length > 1) {
        const nextLevel = [];
        for (let i = 0; i < level.length; i += 2) {
            if (i + 1 < level.length) {
                // Concatenate and hash the pair
                const hash = ethers_1.ethers.keccak256(ethers_1.ethers.concat([level[i], level[i + 1]]));
                nextLevel.push(hash);
            }
            else {
                // Odd node on this level, bubble up unchanged
                nextLevel.push(level[i]);
            }
        }
        level = nextLevel;
    }
    return level[0];
}
async function main() {
    console.log("Starting state anchoring service...");
    if (!PRIVATE_REGISTRY_ADDRESS || !PUBLIC_ANCHOR_ADDRESS || !RELAYER_KEY) {
        console.error("ERROR: Missing required environment variables.");
        console.error("Ensure PRIVATE_REGISTRY_ADDRESS, PUBLIC_ANCHOR_ADDRESS, and RELAYER_KEY are set.");
        process.exit(1);
    }
    // 1. Initialize providers and relayer signer
    const privateProvider = new ethers_1.ethers.JsonRpcProvider(PRIVATE_RPC_URL);
    const publicProvider = new ethers_1.ethers.JsonRpcProvider(PUBLIC_RPC_URL);
    const relayerSigner = new ethers_1.ethers.Wallet(RELAYER_KEY, publicProvider);
    console.log(`Relayer Address: ${relayerSigner.address}`);
    console.log(`Private RPC Endpoint: ${PRIVATE_RPC_URL}`);
    console.log(`Public RPC Endpoint: ${PUBLIC_RPC_URL}`);
    // 2. Fetch registry state from the private chain
    console.log("Reading state from private PrefixRegistry...");
    const registryContract = new ethers_1.ethers.Contract(PRIVATE_REGISTRY_ADDRESS, PRIVATE_REGISTRY_ABI, privateProvider);
    const count = await registryContract.recordCount();
    const privateBlockNumber = await privateProvider.getBlockNumber();
    console.log(`Found ${count} records in private registry at block ${privateBlockNumber}`);
    const leaves = [];
    if (count > 0) {
        // Paginate and read all records
        const [keys, items] = await registryContract.getRecordsPage(0, count);
        // Sort keys and items deterministically by the key value
        const sortedData = keys.map((key, idx) => ({
            key,
            status: items[idx].status
        })).sort((a, b) => a.key.localeCompare(b.key));
        // Compute leaves: keccak256(key + status)
        for (const data of sortedData) {
            const leaf = ethers_1.ethers.solidityPackedKeccak256(["bytes32", "uint8"], [data.key, data.status]);
            leaves.push(leaf);
        }
    }
    // 3. Compute Merkle Root
    const merkleRoot = computeMerkleRoot(leaves);
    console.log(`Computed Merkle Root: ${merkleRoot}`);
    // 4. Send Anchor transaction to the public chain
    console.log("Submitting state anchor to public RegistryAnchor...");
    const anchorContract = new ethers_1.ethers.Contract(PUBLIC_ANCHOR_ADDRESS, PUBLIC_ANCHOR_ABI, relayerSigner);
    try {
        // Send transaction (gasPrice: 0 works for private/consortium chains config)
        const tx = await anchorContract.submitAnchor(merkleRoot, privateBlockNumber, {
            gasLimit: 5000000,
            gasPrice: 0
        });
        console.log(`Transaction broadcasted. Hash: ${tx.hash}`);
        console.log("Waiting for confirmation...");
        const receipt = await tx.wait();
        console.log(`Anchor transaction confirmed in block ${receipt.blockNumber}!`);
        console.log("Bridge sync successful.");
        process.exit(0);
    }
    catch (err) {
        console.error("ERROR submitting anchor transaction:", err.message || err);
        process.exit(1);
    }
}
main().catch((err) => {
    console.error("CRITICAL error in anchor-service execution:", err);
    process.exit(1);
});
