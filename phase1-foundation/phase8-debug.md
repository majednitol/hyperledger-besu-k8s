# Phase 8 Debugging Playbook

> Diagnostic guides and resolutions for issues encountered during Express API Gateway deployment, CORS, and explorer connections in Phase 8.

---

## 1. CORS blocks Dashboard UI queries
* **Symptom**: Inspecting console in browser shows `Access-Control-Allow-Origin` errors when loading prefix metrics.
* **Diagnostics**: Open developer tools (F12) -> Console.
* **Fix**: The API server `10.api/src/server.js` uses Express `cors()` middleware. Ensure it is initialized before routing rules:
  ```javascript
  const cors = require("cors");
  app.use(cors()); // Enables wildcard CORS for development
  ```
  In production, restrict the allowed origins to your actual domain name.

---

## 2. API Gateway returns `401 Unauthorized` on writes
* **Symptom**: Posting to `/api/prefix` returns `401 Unauthorized`.
* **Diagnostics**:
  - Check the request headers inside browser network inspector.
  - Verify that the `Authorization` header has format `Bearer <token>`.
* **Fix**: Ensure that the user obtains a valid JWT token first by logging in to `/api/login` with the pre-configured RIR secret key.

---

## 3. Explorer queries fail with connection timeouts
* **Symptom**: Web3 explorer UI shows "Failed to connect" or "net_peerCount query failed".
* **Diagnostics**: Check if the browser can resolve the JSON-RPC endpoints directly.
* **Common Root Causes**:
  - **Local port-forward missing**: Private block explorer running locally requires port-forwarding the private RPC node (`8545`).
  - **Egress NetworkPolicy blocking**: The public RPC has NetworkPolicies blocking ingress if it is not mapped from the Ingress controller namespace.
  - **Fix**: Establish port forwarding:
    ```bash
    kubectl port-forward svc/rpc-rono 8545:8545 -n besu-private
    ```

---

## 4. Web page assets (CSS/JS) return `404 Not Found`
* **Symptom**: Dashboard loads plain text with no styling; browser console reports `style.css not found`.
* **Common Root Causes**:
  - **Static routing pathing mismatch**: The server cannot resolve the relative path of folders `11.ui` or `12.explorer` relative to the server script.
  - **Fix**: Check `server.js` path joins:
    ```javascript
    app.use("/ui", express.static(path.join(__dirname, "../../11.ui")));
    ```
    This resolves paths correctly regardless of which folder the node process is launched from.

---

## 5. Docker container crashes on startup (OOM or Permission)
* **Symptom**: `api-gateway` pod crashes immediately.
* **Diagnostics**:
  ```bash
  kubectl logs -n besu-app -l app=api-gateway
  ```
* **Common Root Causes**:
  - **Memory Limits exceeded**: Container requests `256Mi` but exceeds it during initialization.
  - **File permissions**: Running as user `node` (UID 1000) but files inside the image are owned by root, causing permission denied when loading scripts.
  - **Fix**: The Dockerfile uses `COPY --chown=node:node` to guarantee correct permissions for the non-root execution context. Increase memory limit to `512Mi` if needed.
