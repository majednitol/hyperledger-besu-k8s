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

// Fetch Healthcare records from the API Gateway
async function fetchRegistry() {
  try {
    const res = await fetch(`${API_BASE}/records?limit=50`);
    if (!res.ok) throw new Error(`HTTP error ${res.status}`);
    const data = await res.json();
    
    document.getElementById("sync-status").innerText = "CONNECTED";
    document.getElementById("sync-status").className = "val text-green";

    registryTableBody.innerHTML = "";
    if (!data.records || data.records.length === 0) {
      registryTableBody.innerHTML = `<tr><td colspan="6" class="text-center text-muted">No medical records found. Registry is empty.</td></tr>`;
      return;
    }

    data.records.forEach(rec => {
      const tr = document.createElement("tr");
      
      const date = new Date(rec.submittedAt * 1000).toLocaleString();
      const shortHash = rec.treatmentHash.substring(0, 12) + "...";
      const shortDoctor = rec.doctor.substring(0, 10) + "...";

      tr.innerHTML = `
        <td class="text-mono">#${rec.key}</td>
        <td class="text-mono">${rec.patientId}</td>
        <td class="text-mono text-green">${rec.diagnosisCode}</td>
        <td class="text-mono text-muted" title="${rec.treatmentHash}">${shortHash}</td>
        <td class="text-mono text-muted" title="${rec.doctor}">${shortDoctor}</td>
        <td class="text-mono text-muted">${date}</td>
      `;
      registryTableBody.appendChild(tr);
    });
    logMsg("Healthcare registry table updated successfully.", "success");
  } catch (err) {
    logMsg(`Failed to query healthcare registry: ${err.message}`, "error");
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

    if (data.total === 0) {
      document.getElementById("public-root").innerText = "No anchors yet";
      document.getElementById("anchored-block").innerText = "N/A";
      document.getElementById("anchored-time").innerText = "N/A";
      return;
    }

    document.getElementById("public-root").innerText = data.merkleRoot;
    document.getElementById("anchored-block").innerText = `#${data.privateBlockNumber}`;
    document.getElementById("anchored-time").innerText = new Date(data.timestamp * 1000).toLocaleString();
    logMsg(`Anchor status updated: root=${data.merkleRoot.substring(0, 10)}... block=${data.privateBlockNumber}`, "info");
  } catch (err) {
    logMsg(`Failed to query anchor status: ${err.message}`, "error");
  }
}

// Form Submission: Submit new medical record
submissionForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  
  const org = document.getElementById("rir-org-select").value;
  const token = document.getElementById("jwt-token").value;
  const diagnosisCode = document.getElementById("prefix-input").value;
  const patientId = parseInt(document.getElementById("asn-input").value);
  
  // Simulate treatment plan hash (in real apps, this is patient data uploaded to IPFS/Secure store)
  const treatmentHash = "0x" + ethers.keccak256(ethers.toUtf8Bytes(`treatment-plan-for-patient-${patientId}-${Date.now()}`)).substring(2);

  logMsg(`Registering medical record: patientId=${patientId} diagnosis=${diagnosisCode} role=${org}...`, "warning");
  submissionResponse.className = "response-box hidden";
  
  try {
    const res = await fetch(`${API_BASE}/record`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`
      },
      body: JSON.stringify({ patientId, diagnosisCode, treatmentHash })
    });

    const data = await res.json();
    if (!res.ok) {
      throw new Error(data.error || `HTTP error ${res.status}`);
    }

    logMsg(`Medical record registered! TxHash: ${data.txHash}`, "success");
    submissionResponse.innerText = `Success! Record confirmed in block #${data.blockNumber}. TxHash: ${data.txHash}`;
    submissionResponse.className = "response-box text-green";

    // Refresh UI
    setTimeout(fetchRegistry, 2000);
  } catch (err) {
    logMsg(`Registration rejected: ${err.message}`, "error");
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
