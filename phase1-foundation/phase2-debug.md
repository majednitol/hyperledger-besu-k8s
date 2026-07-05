# Phase 2 Debugging Playbook

> Diagnostic guides and resolutions for issues encountered during Phase 2 execution.

---

## 1. Genesis Generator Job Fails to Create Configs
* **Symptom**: `kubectl get jobs -n besu-private` shows `generate-genesis` with `0/1` completions, and pod status is `Error` or `CrashLoopBackOff`.
* **Diagnostics**:
  ```bash
  kubectl logs -n besu-private -l job-name=generate-genesis
  kubectl describe job generate-genesis -n besu-private
  ```
* **Common Root Causes**:
  - **Storage Class / PVC Mismatch**: The PVC `genesis-output-pvc` is pending and not bound because there is no matching or default `StorageClass` in the cluster. Run `kubectl get pvc -n besu-private` to check the status. If it's `Pending`, describe it: `kubectl describe pvc genesis-output-pvc -n besu-private`. Resolve by declaring a valid `StorageClass` in `pvc.yaml` (e.g. gp3, standard).
  - **Pod Security Admission (PSA) Rejection**: The namespace PSA is set to `restricted`, but the container settings did not drop all capabilities or ran as root. The `generate-genesis-job.yaml` container configuration drops all capabilities and runs as non-root (UID 1000) to pass PSA enforcement. If it still crashes, check if the cluster enforces stricter UID ranges.

---

## 2. Helper Pod `genesis-extractor` Fails to Start
* **Symptom**: `kubectl get pods -n besu-private` shows `genesis-extractor` stuck in `ContainerCreating` or `ImagePullBackOff`.
* **Diagnostics**:
  ```bash
  kubectl describe pod genesis-extractor -n besu-private
  ```
* **Common Root Causes**:
  - **Namespace PSA Violations**: The helper pod runs as root (alpine image default) in a `restricted` namespace. We must ensure the helper pod's container uses security context settings matching restricted PSA:
    ```yaml
    securityContext:
      runAsNonRoot: true
      runAsUser: 1000
      fsGroup: 1000
      capabilities:
        drop: ["ALL"]
      allowPrivilegeEscalation: false
    ```
    This is fixed in `extract-keys.sh` execution.

---

## 3. cert-manager Certificates Stay in "Issuing" State
* **Symptom**: `kubectl get certificates -n besu-private` shows `READY=False` or `READY=Unknown` for multiple certificates.
* **Diagnostics**:
  ```bash
  kubectl describe certificate validator-afrinic-tls -n besu-private
  kubectl get challenges,orders -n besu-private
  kubectl logs -n cert-manager -l app=cert-manager
  ```
* **Common Root Causes**:
  - **CA Issuer Ready State**: The Issuer `besu-private-ca-issuer` is not ready because the certificate authority keypair secret `besu-private-ca-keypair` was not created.
  - **Fix**: Check issuer status:
    ```bash
    kubectl describe issuer besu-private-ca-issuer -n besu-private
    ```
    Ensure the SelfSigned root CA succeeded and generated the `besu-private-ca-keypair` secret.

---

## 4. `extract-keys.sh` fails with "Secret already exists"
* **Symptom**: Re-running the key extraction script throws K8s API errors and fails to finish ConfigMap/Secret updates.
* **Fix**: Delete existing configurations if performing a full rebuild, or modify the script to use `kubectl apply` with dry-run outputs. The `extract-keys.sh` script is written to generate YAML manifests and apply them natively, resolving override issues.

---

## 5. `static-nodes.json` missing node endpoints
* **Symptom**: Static nodes file is empty `[]` or has missing enodes.
* **Fix**: This happens if the genesis job has not run, or `extract-keys.sh` fails to extract the public keys from `key.pub` files. Ensure you run the script only after the `generate-genesis` job is successful.
