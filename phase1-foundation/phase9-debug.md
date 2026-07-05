# Phase 9 Debugging Playbook

> Diagnostic guides and resolutions for issues encountered during Prometheus metrics scraping, Alertmanager configurations, and Grafana dashboard connections in Phase 9.

---

## 1. Prometheus targets return `DOWN` status
* **Symptom**: Opening Prometheus dashboard -> Status -> Targets shows scrapers for validators are offline (red).
* **Diagnostics**:
  ```bash
  kubectl logs -n besu-app -l app=prometheus
  ```
* **Common Root Causes**:
  - **NetworkPolicy blocking scraper**: The target namespace (`besu-private` or `besu-public`) has a default-deny NetworkPolicy that does not allow incoming TCP traffic on port `9545` from the `besu-app` namespace.
  - **Metrics not enabled on node**: The validator StatefulSet is missing the `--metrics-enabled=true --metrics-port=9545` arguments.
  - **Fix**: Check `netpol-private.yaml` and `netpol-public.yaml` to ensure they allow traffic on port `9545` from source namespace selector matching `besu-app`.

---

## 2. Grafana reports "Prometheus Datasource Error"
* **Symptom**: Dashboards display "datasource not found" or "connection refused".
* **Diagnostics**: Open Grafana -> Connections -> Datasources -> Click Prometheus -> Click "Save & Test".
* **Common Root Causes**:
  - **Incorrect Url**: Grafana configmap sets the URL to `http://prometheus:9090`. If the prometheus service is named differently or deployed in another namespace, it will fail.
  - **Fix**: Verify the prometheus service name:
    ```bash
    kubectl get svc -n besu-app
    ```
    Ensure the datasource URL in `grafana-configmap.yaml` matches the service name.

---

## 3. Prometheus pod remains `Pending` due to PVC
* **Symptom**: `kubectl get pods -n besu-app` shows prometheus pod is stuck pending.
* **Diagnostics**:
  ```bash
  kubectl describe pod -n besu-app -l app=prometheus
  ```
* **Common Root Causes**:
  - **No default StorageClass**: The PVC `prometheus-storage-pvc` requests a volume but the cluster has no default StorageClass provisioned (e.g. on clean bare metal or minikube without hostpath config).
  - **Fix**: Specify an explicit storage class in `prometheus-deployment.yaml` or run in local hostpath mode.

---

## 4. Alertmanager notifications fail to deliver
* **Symptom**: Muted notifications; alerts move to `firing` status in Prometheus but no webhook requests land on the receiver.
* **Diagnostics**:
  ```bash
  kubectl logs -n besu-app -l app=alertmanager
  ```
* **Common Root Causes**:
  - **Invalid Webhook endpoint**: The receiver URL `http://alert-receiver.local/notify` is unreachable from the cluster.
  - **NetworkPolicy blocking egress**: Alertmanager is running inside `besu-app` but egress to the webhook server is denied.
  - **Fix**: Update webhook configurations to a valid routing IP and add egress allow rules to Alertmanager.

---

## 5. Security audit flags `:latest` image tag
* **Symptom**: `phase9-verify.sh` fails with image tag pinning errors.
* **Common Root Causes**:
  - **Template placeholder residue**: A deployment manifest is using a generic tag name or missing the explicit version.
  - **Fix**: Open the flagged yaml file, find the `image:` attribute, and change the tag (e.g. from `hyperledger/besu:latest` to `hyperledger/besu:24.12.2`).
