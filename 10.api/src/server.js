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

// Resolve dynamic organizations
// Fallback to ["doctor", "patient"] if ORG_NAMES is not set
const ORG_NAMES = (process.env.ORG_NAMES || "doctor,patient").split(",").map(o => o.trim());

// Construct RPC URLs and private keys dynamically
const PRIVATE_RPC_URLS = {};
const PRIVATE_KEYS = {};

ORG_NAMES.forEach(org => {
  const envRpc = `RPC_${org.toUpperCase()}_URL`;
  const envKey = `${org.toUpperCase()}_KEY`;

  PRIVATE_RPC_URLS[org] = process.env[envRpc] || `http://rpc-${org}.besu-private.svc.cluster.local:8545`;
  
  // Dev fallback key (pre-funded deployer key)
  PRIVATE_KEYS[org] = process.env[envKey] || "0xae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f";
});

// For local direct calls if DNS fails, add local port fallbacks
PRIVATE_RPC_URLS["doctor_local"] = "http://127.0.0.1:18545";
PRIVATE_RPC_URLS["patient_local"] = "http://127.0.0.1:18545";

const PUBLIC_RPC_URL = process.env.PUBLIC_RPC_URL || "http://127.0.0.1:28545";
const PRIVATE_REGISTRY_ADDRESS = process.env.PRIVATE_REGISTRY_ADDRESS;
const PUBLIC_ANCHOR_ADDRESS = process.env.PUBLIC_ANCHOR_ADDRESS;
const JWT_SECRET = process.env.JWT_SECRET || "dev-healthcare-secret-key-123456789";

// Medical Record ABI
const REGISTRY_ABI = [
  "function submitRecord(uint256 patientId, string calldata diagnosisCode, string calldata treatmentHash) external returns (uint256)",
  "function recordCount() external view returns (uint256)",
  "function getRecordsPage(uint256 offset, uint256 limit) external view returns (uint256[] keys, tuple(uint256 patientId, string diagnosisCode, string treatmentHash, address doctor, uint256 submittedAt, bool active)[] items)",
  "function setDoctorAuthorization(uint256 patientId, address doctor, bool authorized) external"
];

// Anchor ABI
const ANCHOR_ABI = [
  "function latest() external view returns (tuple(bytes32 merkleRoot, uint256 privateBlockNumber, uint256 timestamp))",
  "function totalAnchors() external view returns (uint256)"
];

// Middleware: Authenticate Role token
function authenticateRole(req, res, next) {
  const authHeader = req.headers["authorization"];
  const token = authHeader && authHeader.split(" ")[1];

  if (!token) return res.status(401).json({ error: "Missing authorization token" });

  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err) return res.status(403).json({ error: "Invalid or expired token" });
    
    const org = decoded.org;
    if (!PRIVATE_RPC_URLS[org] && !PRIVATE_RPC_URLS[`${org}_local`]) {
      return res.status(403).json({ error: "Unauthorized role entity" });
    }
    
    req.roleOrg = org;
    next();
  });
}

// 1. Authenticated Route: Submit Medical Record (Write to Private Chain)
app.post("/api/record", authenticateRole, async (req, res) => {
  const { patientId, diagnosisCode, treatmentHash } = req.body;
  if (patientId === undefined || !diagnosisCode || !treatmentHash) {
    return res.status(400).json({ error: "Parameters patientId, diagnosisCode, and treatmentHash are required" });
  }

  const org = req.roleOrg;
  // Try local fallback first if running locally, otherwise use cluster local DNS
  let rpcUrl = PRIVATE_RPC_URLS[org];
  if (process.env.NODE_ENV !== "production") {
    rpcUrl = PRIVATE_RPC_URLS[`${org}_local`] || rpcUrl;
  }
  const privateKey = PRIVATE_KEYS[org];

  if (!PRIVATE_REGISTRY_ADDRESS) {
    return res.status(500).json({ error: "PRIVATE_REGISTRY_ADDRESS is not configured" });
  }

  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);
    const contract = new ethers.Contract(PRIVATE_REGISTRY_ADDRESS, REGISTRY_ABI, wallet);

    console.log(`Entity ${org} submitting record for patient ${patientId} to private chain...`);
    const tx = await contract.submitRecord(Number(patientId), diagnosisCode, treatmentHash, {
      gasLimit: 3000000,
      gasPrice: 0 // zero-gas configuration
    });

    const receipt = await tx.wait();
    res.json({
      message: "Medical record submitted successfully",
      txHash: tx.hash,
      blockNumber: receipt.blockNumber,
      org: org
    });
  } catch (err) {
    console.error("Submission failed:", err.message || err);
    res.status(500).json({ error: "Transaction submission failed", details: err.message });
  }
});

// 2. Open Route: Fetch Records (Read from Private Chain)
app.get("/api/records", async (req, res) => {
  const offset = parseInt(req.query.offset || "0");
  const limit = parseInt(req.query.limit || "20");

  if (!PRIVATE_REGISTRY_ADDRESS) {
    return res.status(500).json({ error: "PRIVATE_REGISTRY_ADDRESS is not configured" });
  }

  try {
    let rpcUrl = PRIVATE_RPC_URLS.doctor;
    if (process.env.NODE_ENV !== "production") {
      rpcUrl = PRIVATE_RPC_URLS["doctor_local"] || rpcUrl;
    }
    const privateProvider = new ethers.JsonRpcProvider(rpcUrl);
    const contract = new ethers.Contract(PRIVATE_REGISTRY_ADDRESS, REGISTRY_ABI, privateProvider);

    const count = await contract.recordCount();
    if (count === BigInt(0) || offset >= count) {
      return res.json({ total: Number(count), records: [] });
    }

    const [keys, items] = await contract.getRecordsPage(offset, limit);
    
    const records = keys.map((key, idx) => ({
      key: key.toString(),
      patientId: items[idx].patientId.toString(),
      diagnosisCode: items[idx].diagnosisCode,
      treatmentHash: items[idx].treatmentHash,
      doctor: items[idx].doctor,
      submittedAt: Number(items[idx].submittedAt),
      active: items[idx].active
    }));

    res.json({
      total: Number(count),
      offset,
      limit,
      records
    });
  } catch (err) {
    console.error("Failed to fetch records:", err.message || err);
    res.status(500).json({ error: "Failed to fetch records", details: err.message });
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

    const total = await contract.totalAnchors();
    if (total === BigInt(0)) {
      return res.json({ message: "No anchors yet", total: 0 });
    }

    const latestAnchor = await contract.latest();
    res.json({
      total: Number(total),
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
  console.log(`Configured entities: ${ORG_NAMES.join(", ")}`);
});
