# Blockscout Integration with Hyperledger Besu

This document outlines the architecture, resource implications, environment variable configurations, and Kubernetes manifests required to deploy **Blockscout** on our Hyperledger Besu dual-network cluster.

---

## 1. Architectural Overview

Blockscout is a feature-rich, open-source blockchain explorer. Unlike our lightweight static explorers, Blockscout actively indexes the chain, meaning it parses all blocks, transactions, events, and balances into a relational database to enable advanced searches (like token transfers, ERC-20 logs, and contract source verification).

```
┌──────────────────┐       ┌──────────────────────┐
│  Besu RPC Node   │◄──────┤  Blockscout Backend  │
│    (Archive)     │       │   (Elixir Engine)    │
└──────────────────┘       └──────────┬───────────┘
                                      │   ▲
                                      ▼   │
                       ┌──────────────────────────────┐
                       │  PostgreSQL Database (PV)    │
                       └──────────────────────────────┘
```

### Components Required
1. **PostgreSQL Database**: Stores block history, balances, address mappings, and tokens data.
2. **Redis Cache**: Used by the Elixir engine for real-time WebSocket subscriptions and UI caching.
3. **Blockscout Engine**: Runs the indexer and serves HTTP API routes (port 4000).
4. **Blockscout UI**: The modern Next.js-based frontend interacting with the backend.

---

## 2. Besu Node Prerequisites

For Blockscout to correctly resolve historic account balances and address state trees, the target Besu node must be run as an **Archive Node**:
- Ensure the RPC node deployment does **NOT** contain pruning options (like `--data-storage-format=BONSAI` with aggressive pruning).
- The JSON-RPC APIs exposed must include `eth`, `net`, `web3`, and optionally `txpool`.

---

## 3. Kubernetes Deployment Manifests

Below is the complete, self-contained manifest package to deploy Blockscout pointing to our Public Besu Network.

### 3.1 Database & Redis Stateful Sets

Save this file as `14.blockscout/blockscout-services.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: blockscout-db-pvc
  namespace: besu-app
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blockscout-db
  namespace: besu-app
  labels:
    app: blockscout-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: blockscout-db
  template:
    metadata:
      labels:
        app: blockscout-db
    spec:
      containers:
        - name: postgres
          image: postgres:15-alpine
          env:
            - name: POSTGRES_DB
              value: blockscout
            - name: POSTGRES_USER
              value: postgres
            - name: POSTGRES_PASSWORD
              value: blockscout_db_secret_pass
          ports:
            - containerPort: 5432
              name: db
          resources:
            requests:
              cpu: "100m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          volumeMounts:
            - name: db-data
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: db-data
          persistentVolumeClaim:
            claimName: blockscout-db-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: blockscout-db
  namespace: besu-app
spec:
  ports:
    - port: 5432
  selector:
    app: blockscout-db
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blockscout-redis
  namespace: besu-app
  labels:
    app: blockscout-redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: blockscout-redis
  template:
    metadata:
      labels:
        app: blockscout-redis
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          ports:
            - containerPort: 6379
              name: redis
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "100m"
              memory: "128Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: blockscout-redis
  namespace: besu-app
spec:
  ports:
    - port: 6379
  selector:
    app: blockscout-redis
```

### 3.2 Blockscout Monolithic Engine & UI

Save this file as `14.blockscout/blockscout-app.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blockscout
  namespace: besu-app
  labels:
    app: blockscout
spec:
  replicas: 1
  selector:
    matchLabels:
      app: blockscout
  template:
    metadata:
      labels:
        app: blockscout
    spec:
      containers:
        - name: blockscout
          image: blockscout/blockscout:v6.2.0
          env:
            - name: PORT
              value: "4000"
            - name: COIN
              value: "RIR"
            - name: ETHEREUM_JSONRPC_VARIANT
              value: "besu"
            - name: ETHEREUM_JSONRPC_HTTP_URL
              value: "http://rpc-public.besu-public.svc.cluster.local:8545"
            - name: ETHEREUM_JSONRPC_TRACE_URL
              value: "http://rpc-public.besu-public.svc.cluster.local:8545"
            - name: DATABASE_URL
              value: "postgresql://postgres:blockscout_db_secret_pass@blockscout-db:5432/blockscout"
            - name: REDIS_URL
              value: "redis://blockscout-redis:6379/0"
            - name: SECRET_KEY_BASE
              value: "super_secret_key_base_must_be_64_bytes_long_12345678901234567890123456789012"
            - name: INDEXER_DISABLE_PENDING_TRANSACTIONS_FETCHER
              value: "true"
          ports:
            - containerPort: 4000
              name: http
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "1.5"
              memory: "2Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: blockscout
  namespace: besu-app
spec:
  ports:
    - port: 4000
      targetPort: 4000
      name: http
  selector:
    app: blockscout
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: blockscout-ingress
  namespace: besu-app
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/limit-rps: "20"
spec:
  rules:
    - host: explorer.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: blockscout
                port:
                  number: 4000
```

---

## 4. Evaluation and Comparison

Before replacing our static client-side explorers, consider the resource trade-offs:

| Metric | Web3 Static Explorer (Current) | Blockscout (EVM Indexer) |
|---|---|---|
| **EVM Database size** | None (0 MB) | Postgres PVC (`20GB+` state storage) |
| **CPU/RAM requirements** | Negligible (Served as static HTML) | Requires minimum `1.5 CPU` and `2GB RAM` |
| **Indexing latency** | Real-time (pulls headers in browser) | Delayed by indexer queues (5-30s) |
| **Advanced Search** | No (cannot search token hashes or internal txs) | Yes (full history indexed and searchable) |

### Recommendation
For a production deployment where operators require searching detailed ERC-20 contract code logs, **Blockscout** is the industry standard. However, to keep developer test environments light, our static Web3 explorer is more practical.
