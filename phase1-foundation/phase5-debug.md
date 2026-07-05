# Phase 5 Debugging Playbook

> Diagnostic guides and resolutions for issues encountered during Let's Encrypt ClusterIssuer setup and public genesis generation in Phase 5.

---

## 1. Let's Encrypt ClusterIssuer stays "False" or "Unknown"
* **Symptom**: `kubectl get clusterissuers` shows `Ready: False` for `letsencrypt-staging` or `letsencrypt-prod`.
* **Diagnostics**:
  ```bash
  kubectl describe clusterissuer letsencrypt-prod
  kubectl logs -n cert-manager -l app=cert-manager
  ```
* **Common Root Causes**:
  - **Connection/DNS Timeout**: cert-manager cannot resolve or connect to the ACME directory endpoint (e.g., `acme-v02.api.letsencrypt.org`).
  - **Invalid Email Address**: Let's Encrypt rejects registration if the email format is invalid.
  - **Fix**: Update the `email` field inside `letsencrypt-issuer.yaml` to a valid administrator address, verify CoreDNS resolver is working, and re-apply.

---

## 2. ACME Challenge Fails / Certificate Stays "Issuing"
* **Symptom**: `kubectl get certificates -n besu-public` shows the test certificate is not ready.
* **Diagnostics**:
  ```bash
  kubectl describe certificate test-letsencrypt-cert -n besu-public
  kubectl get challenges,orders -n besu-public
  kubectl describe challenge -n besu-public
  ```
* **Common Root Causes**:
  - **Ingress Controller Unreachable**: Let's Encrypt servers attempt to resolve your domain (e.g., `test-besu.yourdomain.com`) and fetch a challenge token via HTTP-01 on port 80. If your ingress controller is behind a NAT or has no public IP, it will fail.
  - **DNS Record Missing**: The domain name does not have a DNS A record pointing to the public IP of your Kubernetes Ingress Controller.
  - **Fix**: Ensure your external DNS matches the Ingress IP. If running in a local environment (Minikube/Kind), use `minikube tunnel` or a DNS tunnel to expose port 80/443.

---

## 3. Public Genesis Job fails PSA Rejection
* **Symptom**: `generate-public-genesis` job fails to schedule or remains pending.
* **Diagnostics**:
  ```bash
  kubectl describe job generate-public-genesis -n besu-public
  ```
* **Common Root Causes**:
  - **PSA Namespace Rule Violation**: The `besu-public` namespace enforces `restricted` Pod Security Admission, but the container security settings were omitted.
  - **Fix**: Verify that `generate-genesis-job.yaml` has the required `securityContext` parameters (runAsNonRoot: true, runAsUser: 1000, drop all capabilities).

---

## 4. `extract-keys.sh` fails "ERROR: Expected 5 validator keys..."
* **Symptom**: Key extraction script fails when checking keys counts.
* **Common Root Causes**:
  - **Job Execution Failed**: The genesis Job crashed during execution and did not write files to the PVC.
  - **Fix**: Check Job container logs to diagnose Besu generation errors:
    ```bash
    kubectl logs -n besu-public -l job-name=generate-public-genesis
    ```

---

## 5. Accidental Cross-talk / Permissioning present
* **Symptom**: `phase5-verify.sh` fails because permissioning addresses (0x...9999 or 0x...8888) are found in the public genesis.
* **Common Root Causes**:
  - **Copy-Paste Error**: The public `qbftConfigFile.json` was copied from the private network config without removing the `alloc` contract bindings.
  - **Fix**: Open `public-network/2.genesis/qbftConfigFile.json`, verify that the `alloc` object is completely empty (`"alloc": {}`), and re-run the genesis Job.
