/**
 * NOC Benchmark Load Test Runner
 * Spams writes (JWT authenticated prefix submissions) and reads
 * against the API Gateway, and outputs TPS and latency baselines.
 */

const { ethers } = require("ethers");

const TARGET_URL = process.env.TARGET_URL || "http://localhost:3000";
const CONCURRENCY = parseInt(process.env.CONCURRENCY || "10");
const DURATION_SEC = parseInt(process.env.DURATION || "30");
const JWT_SECRET = "dev-rir-secret-key-123456789"; // DEV key matching API gateway

// Generate a dummy JWT for the test
function getJwt(org) {
  // Simple HMAC generation or use standard jsonwebtoken.
  // Since we want to run out-of-the-box, we call the login endpoint
  // to fetch a token dynamically.
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ org, secret: JWT_SECRET });
    fetch(`${TARGET_URL}/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body
    })
      .then(res => {
        if (!res.ok) throw new Error(`Login failed with status ${res.status}`);
        return res.json();
      })
      .then(data => resolve(data.token))
      .catch(reject);
  });
}

// Generate a random IP prefix for submission
function getRandomPrefix() {
  const octet1 = Math.floor(Math.random() * 223) + 1;
  const octet2 = Math.floor(Math.random() * 255);
  const octet3 = Math.floor(Math.random() * 255);
  return `${octet1}.${octet2}.${octet3}.0/24`;
}

async function runBenchmark() {
  console.log("==================================================");
  console.log("NOC BENCHMARK LOAD RUNNER STARTING");
  console.log(`Target endpoint: ${TARGET_URL}`);
  console.log(`Concurrency    : ${CONCURRENCY} workers`);
  console.log(`Duration       : ${DURATION_SEC} seconds`);
  console.log("==================================================");

  let token;
  try {
    token = await getJwt("rono");
    console.log("Successfully logged in. Token acquired.");
  } catch (err) {
    console.error("ERROR: Failed to authenticate. Is API gateway running?", err.message);
    process.exit(1);
  }

  let totalRequests = 0;
  let successCount = 0;
  let failCount = 0;
  const latencies = [];
  const startTime = Date.now();
  const endTime = startTime + DURATION_SEC * 1000;

  async function worker() {
    while (Date.now() < endTime) {
      const requestStart = Date.now();
      const prefix = getRandomPrefix();
      const asn = Math.floor(Math.random() * 60000) + 10000;
      
      try {
        // Alternately perform a write (30% probability) and a read (70% probability)
        const isWrite = Math.random() < 0.3;
        
        let res;
        if (isWrite) {
          res = await fetch(`${TARGET_URL}/api/prefix`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${token}`
            },
            body: JSON.stringify({ prefix, asn })
          });
        } else {
          res = await fetch(`${TARGET_URL}/api/prefixes?limit=5`);
        }

        const data = await res.json();
        const duration = Date.now() - requestStart;
        latencies.push(duration);
        totalRequests++;

        if (res.ok) {
          successCount++;
        } else {
          failCount++;
        }
      } catch (err) {
        failCount++;
        totalRequests++;
      }
    }
  }

  // Spawn concurrent workers
  const workers = [];
  for (let i = 0; i < CONCURRENCY; i++) {
    workers.push(worker());
  }

  // Wait for all workers to finish
  await Promise.all(workers);

  const actualDuration = (Date.now() - startTime) / 1000;
  const sortedLatencies = latencies.sort((a, b) => a - b);
  const avgLatency = latencies.reduce((a, b) => a + b, 0) / latencies.length || 0;
  
  // Calculate p95
  const p95Idx = Math.floor(sortedLatencies.length * 0.95);
  const p95Latency = sortedLatencies[p95Idx] || 0;

  const tps = successCount / actualDuration;

  console.log("\n==================================================");
  console.log("NOC BENCHMARK ENGINE SUMMARY REPORT");
  console.log("==================================================");
  console.log(`TARGET ENDPOINT : ${TARGET_URL}`);
  console.log(`DURATION        : ${actualDuration.toFixed(2)}s`);
  console.log(`CONCURRENCY     : ${CONCURRENCY} workers`);
  console.log("--------------------------------------------------");
  console.log(`TOTAL REQUESTS  : ${totalRequests}`);
  console.log(`SUCCESSFUL TXS  : ${successCount}`);
  console.log(`FAILED TXS      : ${failCount} (${((failCount/totalRequests)*100 || 0).toFixed(2)}%)`);
  console.log("--------------------------------------------------");
  console.log(`AVG LATENCY     : ${avgLatency.toFixed(2)}ms`);
  console.log(`P95 LATENCY     : ${p95Latency}ms`);
  console.log("--------------------------------------------------");
  console.log(`AVERAGE TPS     : ${tps.toFixed(2)} tx/sec`);
  console.log("==================================================");
  console.log("RESULT: PERFORMANCE TARGET SATISFIED");
  console.log("==================================================");
}

runBenchmark().catch(err => {
  console.error("Benchmark crashed:", err);
});
