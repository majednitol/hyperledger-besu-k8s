const express = require("express");
const cors = require("cors");
const jwt = require("jsonwebtoken");
const { ethers } = require("ethers");
require("dotenv").config();

const path = require("path");

const app = express();
app.use(cors());
app.use(express.json());

// Serve static assets for Dashboard and Explorers
app.use("/ui", express.static(path.join(__dirname, "../../11.ui")));
app.use("/explorer-private", express.static(path.join(__dirname, "../../12.explorer/explorer-private")));
app.use("/explorer-public", express.static(path.join(__dirname, "../../12.explorer/explorer-public")));

const PORT = process.env.PORT || 3000;

// Configuration
const PRIVATE_RPC_URLS = {
  afrinic: process.env.RPC_AFRINIC_URL || "http://127.0.0.1:8545",
  apnic: process.env.RPC_APNIC_URL || "http://127.0.0.1:8545",
  rono: process.env.RPC_RONO_URL || "http://127.0.0.1:8545"
};

const PUBLIC_RPC_URL = process.env.PUBLIC_RPC_URL || "http://127.0.0.1:8545";
const PRIVATE_REGISTRY_ADDRESS = process.env.PRIVATE_REGISTRY_ADDRESS;
const PUBLIC_ANCHOR_ADDRESS = process.env.PUBLIC_ANCHOR_ADDRESS;
const JWT_SECRET = process.env.JWT_SECRET || "dev-rir-secret-key-123456789";

// Private Keys for signing on private network (pre-funded in genesis)
const RIR_PRIVATE_KEYS = {
  afrinic: process.env.AFRINIC_KEY || "0xae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f",
  apnic: process.env.APNIC_KEY || "0xae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f",
  rono: process.env.RONO_KEY || "0xae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f"
};

// ABI Skeletons
const REGISTRY_ABI = [
  "function submitRecord(string calldata prefix, uint32 asn) external returns (bytes32)",
  "function recordCount() external view returns (uint256)",
  "function getRecordsPage(uint256 offset, uint256 limit) external view returns (bytes32[] keys, tuple(string prefix, uint32 asn, address submittedBy, uint8 status, uint256 submittedAt, uint256 updatedAt)[] items)"
];

const ANCHOR_ABI = [
  "function latest() external view returns (tuple(bytes32 merkleRoot, uint256 privateBlockNumber, uint256 timestamp))"
];

// Middleware: Authenticate RIR token
function authenticateRIR(req, res, next) {
  const authHeader = req.headers["authorization"];
  const token = authHeader && authHeader.split(" ")[1];

  if (!token) return res.status(401).json({ error: "Missing authorization token" });

  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err) return res.status(403).json({ error: "Invalid or expired token" });
    
    const org = decoded.org;
    if (!PRIVATE_RPC_URLS[org]) {
      return res.status(403).json({ error: "Unauthorized RIR organization" });
    }
    
    req.rirOrg = org;
    next();
  });
}

// 1. Authenticated Route: Submit Prefix (Write to Private Chain)
app.post("/api/prefix", authenticateRIR, async (req, res) => {
  const { prefix, asn } = req.body;
  if (!prefix || !asn) {
    return res.status(400).json({ error: "Parameters prefix and asn are required" });
  }

  const org = req.rirOrg;
  const rpcUrl = PRIVATE_RPC_URLS[org];
  const privateKey = RIR_PRIVATE_KEYS[org];

  if (!PRIVATE_REGISTRY_ADDRESS) {
    return res.status(500).json({ error: "PRIVATE_REGISTRY_ADDRESS is not configured" });
  }

  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);
    const contract = new ethers.Contract(PRIVATE_REGISTRY_ADDRESS, REGISTRY_ABI, wallet);

    console.log(`RIR ${org} submitting prefix ${prefix} with ASN ${asn} to private chain...`);
    const tx = await contract.submitRecord(prefix, asn, {
      gasLimit: 3000000,
      gasPrice: 0 // private network gas configuration
    });

    const receipt = await tx.wait();
    res.json({
      message: "Prefix submitted successfully",
      txHash: tx.hash,
      blockNumber: receipt.blockNumber,
      org: org
    });
  } catch (err) {
    console.error("Submission failed:", err.message || err);
    res.status(500).json({ error: "Transaction submission failed", details: err.message });
  }
});

// 2. Open Route: Fetch Prefixes (Read from Public Chain)
app.get("/api/prefixes", async (req, res) => {
  const offset = parseInt(req.query.offset || "0");
  const limit = parseInt(req.query.limit || "20");

  if (!PRIVATE_REGISTRY_ADDRESS) {
    return res.status(500).json({ error: "PRIVATE_REGISTRY_ADDRESS is not configured" });
  }

  try {
    // Read from the public node (which mirrors state after validator sync/bridge)
    // Wait, the PrefixRegistry contract is deployed on the private network.
    // In our architecture, reads can be directed to the private RPC nodes (load balanced) or public RPC nodes.
    // Since PrefixRegistry is on the private network, we query the private RPC endpoint forPrefixRegistry entries.
    // Let's use the public endpoint if they are mirrored, or query the private load balancer for RIR entries:
    // The master plan says: "unauthenticated but independently rate-limited reads from public RPC/anchor status"
    // Wait, if PrefixRegistry is only on the private chain, public RPC can only access RegistryAnchor!
    // So to read PrefixRegistry entries, the API must query the PRIVATE RPC endpoint (read-only queries).
    // Let's direct PrefixRegistry reads to the private provider, and Anchor reads to the public provider!
    // This is correct because the public chain only contains anchors (RegistryAnchor.sol), while PrefixRegistry.sol resides on the private chain.
    const privateProvider = new ethers.JsonRpcProvider(PRIVATE_RPC_URLS.rono); // Query via private node
    const contract = new ethers.Contract(PRIVATE_REGISTRY_ADDRESS, REGISTRY_ABI, privateProvider);

    const count = await contract.recordCount();
    if (count === BigInt(0) || offset >= count) {
      return res.json({ total: Number(count), records: [] });
    }

    const [keys, items] = await contract.getRecordsPage(offset, limit);
    
    const records = keys.map((key, idx) => ({
      key,
      prefix: items[idx].prefix,
      asn: Number(items[idx].asn),
      submittedBy: items[idx].submittedBy,
      status: Number(items[idx].status),
      submittedAt: Number(items[idx].submittedAt),
      updatedAt: Number(items[idx].updatedAt)
    }));

    res.json({
      total: Number(count),
      offset,
      limit,
      records
    });
  } catch (err) {
    console.error("Failed to fetch prefixes:", err.message || err);
    res.status(500).json({ error: "Failed to fetch prefixes", details: err.message });
  }
});

// 3. Open Route: Fetch latest Anchor (Read from Public Chain)
app.get("/api/anchor", async (req, res) => {
  if (!PUBLIC_ANCHOR_ADDRESS) {
    return res.status(500).json({ error: "PUBLIC_ANCHOR_ADDRESS is not configured" });
  }

  try {
    const publicProvider = new ethers.JsonRpcProvider(PUBLIC_RPC_URL);
    const contract = new ethers.Contract(PUBLIC_ANCHOR_ADDRESS, ANCHOR_ABI, publicProvider);

    const latestAnchor = await contract.latest();
    res.json({
      merkleRoot: latestAnchor.merkleRoot,
      privateBlockNumber: Number(latestAnchor.privateBlockNumber),
      timestamp: Number(latestAnchor.timestamp)
    });
  } catch (err) {
    console.error("Failed to fetch latest anchor:", err.message || err);
    res.status(500).json({ error: "Failed to fetch latest anchor", details: err.message });
  }
});

// Login helper to issue JWT tokens for testing/development
app.post("/api/login", (req, res) => {
  const { org, secret } = req.body;
  if (!org || !secret) {
    return res.status(400).json({ error: "Parameters org and secret are required" });
  }
  
  if (secret !== JWT_SECRET) {
    return res.status(401).json({ error: "Invalid secret credential" });
  }

  const token = jwt.sign({ org }, JWT_SECRET, { expiresIn: "24h" });
  res.json({ token });
});

app.listen(PORT, () => {
  console.log(`API Gateway is running on port ${PORT}`);
});
