const API_BASE = "/api";

const logConsole = document.getElementById("console-log");
const registryTableBody = document.getElementById("registry-table-body");
const submissionForm = document.getElementById("submission-form");
const submissionResponse = document.getElementById("submission-response");

// Helper to append log messages to console
function logMsg(msg, type = "info") {
  const div = document.createElement("div");
  const time = new Date().toLocaleTimeString();
  let colorClass = "text-muted";
  if (type === "success") colorClass = "text-green";
  if (type === "error") colorClass = "text-red";
  if (type === "warning") colorClass = "text-amber";
  
  div.innerHTML = `<span class="text-muted">[${time}]</span> <span class="${colorClass}">${msg}</span>`;
  logConsole.appendChild(div);
  logConsole.scrollTop = logConsole.scrollHeight;
}

// Fetch RIR prefix records from the API Gateway
async function fetchRegistry() {
  try {
    const res = await fetch(`${API_BASE}/prefixes?limit=50`);
    if (!res.ok) throw new Error(`HTTP error ${res.status}`);
    const data = await res.json();
    
    document.getElementById("sync-status").innerText = "CONNECTED";
    document.getElementById("sync-status").className = "val text-green";

    registryTableBody.innerHTML = "";
    if (!data.records || data.records.length === 0) {
      registryTableBody.innerHTML = `<tr><td colspan="6" class="text-center text-muted">No records found. Registry is empty.</td></tr>`;
      return;
    }

    data.records.forEach(rec => {
      const tr = document.createElement("tr");
      
      let statusLabel = "PENDING";
      let statusClass = "status-pending";
      if (rec.status === 1) {
        statusLabel = "VALIDATED";
        statusClass = "status-validated";
      } else if (rec.status === 2) {
        statusLabel = "REVOKED";
        statusClass = "status-revoked";
      }

      const date = new Date(rec.submittedAt * 1000).toLocaleString();
      const shortKey = rec.key.substring(0, 10) + "..." + rec.key.substring(rec.key.length - 8);

      tr.innerHTML = `
        <td class="text-mono">${rec.prefix}</td>
        <td class="text-mono">${rec.asn}</td>
        <td class="text-mono">${rec.submittedBy.substring(0, 10)}...</td>
        <td><span class="status-badge ${statusClass}">${statusLabel}</span></td>
        <td class="text-mono text-muted">${date}</td>
        <td class="text-mono text-muted" title="${rec.key}">${shortKey}</td>
      `;
      registryTableBody.appendChild(tr);
    });
    logMsg("Registry table updated successfully.", "success");
  } catch (err) {
    logMsg(`Failed to query registry table: ${err.message}`, "error");
    document.getElementById("sync-status").innerText = "DISCONNECTED";
    document.getElementById("sync-status").className = "val text-red";
  }
}

// Fetch latest public anchor proof
async function fetchAnchor() {
  try {
    const res = await fetch(`${API_BASE}/anchor`);
    if (!res.ok) throw new Error(`HTTP error ${res.status}`);
    const data = await res.json();

    document.getElementById("public-root").innerText = data.merkleRoot;
    document.getElementById("anchored-block").innerText = `#${data.privateBlockNumber}`;
    document.getElementById("anchored-time").innerText = new Date(data.timestamp * 1000).toLocaleString();
    logMsg(`Anchor status updated: root=${data.merkleRoot.substring(0, 10)}... block=${data.privateBlockNumber}`, "info");
  } catch (err) {
    logMsg(`Failed to query anchor status: ${err.message}`, "error");
  }
}

// Form Submission: Submit new prefix
submissionForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  
  const org = document.getElementById("rir-org-select").value;
  const token = document.getElementById("jwt-token").value;
  const prefix = document.getElementById("prefix-input").value;
  const asn = parseInt(document.getElementById("asn-input").value);

  logMsg(`Initiating transmission: prefix=${prefix} asn=${asn} org=${org}...`, "warning");
  submissionResponse.className = "response-box hidden";
  
  try {
    const res = await fetch(`${API_BASE}/prefix`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`
      },
      body: JSON.stringify({ prefix, asn })
    });

    const data = await res.json();
    if (!res.ok) {
      throw new Error(data.error || `HTTP error ${res.status}`);
    }

    logMsg(`Transaction confirmed! TxHash: ${data.txHash}`, "success");
    submissionResponse.innerText = `Success! Transaction confirmed in block #${data.blockNumber}. TxHash: ${data.txHash}`;
    submissionResponse.className = "response-box text-green";

    // Refresh UI
    setTimeout(fetchRegistry, 2000);
  } catch (err) {
    logMsg(`Transmission rejected: ${err.message}`, "error");
    submissionResponse.innerText = `Error: ${err.message}`;
    submissionResponse.className = "response-box text-red";
  }
});

// Setup continuous updates
async function init() {
  logMsg("Connecting to API Gateway...");
  await fetchRegistry();
  await fetchAnchor();
  
  // Set intervals
  setInterval(fetchRegistry, 10000);
  setInterval(fetchAnchor, 15000);
}

init();
