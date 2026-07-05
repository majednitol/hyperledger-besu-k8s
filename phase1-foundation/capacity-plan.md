# Phase 1 — Capacity Plan

> Baseline sizing for the Hyperledger Besu dual-network Kubernetes deployment.
> These values feed into `config.env` resource variables and all PVC/resource-request manifests in Phases 2–6.

---

## Compute Sizing

### Private Network (`besu-private` namespace)

| Component | Count | CPU Request | CPU Limit | Memory Request | Memory Limit | Disk |
|-----------|-------|-------------|-----------|----------------|--------------|------|
| Validators (StatefulSet) | 7 | 2 vCPU | 4 vCPU | 4Gi | 8Gi | 100Gi PVC |
| Bootnodes (Deployment) | 2 | 1 vCPU | 2 vCPU | 2Gi | 4Gi | emptyDir |
| RPC Nodes (Deployment) | 6 | 1 vCPU | 2 vCPU | 2Gi | 4Gi | emptyDir |
| Tessera (optional) | 0–6 | 0.5 vCPU | 1 vCPU | 1Gi | 2Gi | 10Gi PVC |
| **Total (no Tessera)** | **15** | **23 vCPU** | **46 vCPU** | **46Gi** | **92Gi** | **700Gi** |

### Public Network (`besu-public` namespace)

| Component | Count | CPU Request | CPU Limit | Memory Request | Memory Limit | Disk |
|-----------|-------|-------------|-----------|----------------|--------------|------|
| Validators (StatefulSet) | 5 | 2 vCPU | 4 vCPU | 4Gi | 8Gi | 100Gi PVC |
| Bootnodes (Deployment) | 2 | 1 vCPU | 2 vCPU | 2Gi | 4Gi | emptyDir |
| RPC Nodes (Deployment, HPA) | 3–8 | 0.5 vCPU | 1 vCPU | 1Gi | 2Gi | emptyDir |
| **Total (min replicas)** | **10** | **14.5 vCPU** | **29 vCPU** | **27Gi** | **54Gi** | **500Gi** |

### Application Layer (`besu-app` namespace)

| Component | Count | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------|-------------|-----------|----------------|--------------|
| API Server | 2 | 0.5 vCPU | 1 vCPU | 512Mi | 1Gi |
| UI (frontend) | 2 | 0.25 vCPU | 0.5 vCPU | 256Mi | 512Mi |
| Explorer (private) | 1 | 0.5 vCPU | 1 vCPU | 1Gi | 2Gi |
| Explorer (public) | 1 | 0.5 vCPU | 1 vCPU | 1Gi | 2Gi |
| Bridge CronJob | 1 (periodic) | 0.25 vCPU | 0.5 vCPU | 256Mi | 512Mi |
| Prometheus | 1 | 1 vCPU | 2 vCPU | 2Gi | 4Gi |
| Grafana | 1 | 0.5 vCPU | 1 vCPU | 512Mi | 1Gi |
| **Total** | **9** | **4 vCPU** | **8 vCPU** | **5.5Gi** | **11Gi** |

### Cluster Total (baseline)

| Metric | Value |
|--------|-------|
| Total vCPU (requests) | ~41.5 vCPU |
| Total vCPU (limits) | ~83 vCPU |
| Total Memory (requests) | ~78.5 Gi |
| Total Memory (limits) | ~157 Gi |
| Total Persistent Disk | ~1.2 TiB |
| Recommended node pool | 6–8 nodes × 8 vCPU / 32Gi RAM |

---

## Disk Growth Estimates

### QBFT Block Production Rate
- Block period: 5 seconds
- Blocks per day: 17,280
- Blocks per year: 6,307,200

### Per-Block Size (estimates)

| Scenario | Block Size | Daily Growth | 100Gi Lasts |
|----------|-----------|--------------|-------------|
| Empty blocks (idle) | ~0.5 KB | ~8.6 MB | ~31 years |
| Low activity (1–5 txn/block) | ~1–5 KB | ~17–86 MB | ~3–16 years |
| Moderate (50–100 txn/block) | ~50–100 KB | ~864 MB – 1.7 GB | ~60–115 days |
| High (1000+ txn/block) | ~1 MB+ | ~17 GB+ | ~6 days |

### Recommendations
1. **Low-activity phase** (initial deployment): 100Gi PVC is sufficient
2. **Growth triggers**: Set up disk usage alerts at 70% and 80% capacity
3. **Pruning**: Enable `--pruning-enabled=true` (Bonsai state trie) on RPC/full nodes
4. **Archive nodes**: Run 1 dedicated archive node per network (no pruning) behind explorer only
5. **Revisit**: After Phase 10 load test, update PVC sizes based on real growth data

---

## Multi-AZ Distribution

### Requirements

| Network | Validator Count | QBFT Fault Tolerance | Min AZs | Strategy |
|---------|----------------|---------------------|---------|----------|
| Private | 7 | ⌊(7-1)/3⌋ = 2 faults | 3 AZs | Spread validators 3-2-2 across AZs |
| Public | 5 | ⌊(5-1)/3⌋ = 1 fault | 2 AZs | Spread validators 3-2 across AZs |

### Implementation
- Use `podAntiAffinity` with `topologyKey: topology.kubernetes.io/zone` (already in master plan Section 4.3)
- Use `preferredDuringSchedulingIgnoredDuringExecution` (soft anti-affinity) to avoid scheduling failures when AZ capacity is uneven
- Node pools must span the required AZ count

### PodDisruptionBudget Constraints
- **Private**: `maxUnavailable: 1` on 7 validators — leaves 1 fault margin during maintenance
- **Public**: `maxUnavailable: 1` on 5 validators — **zero margin** during maintenance; treat validator alerts as blocking

---

## Backup & Storage Considerations

| Item | Backup Frequency | Retention | Method |
|------|-----------------|-----------|--------|
| Validator chain data (PVCs) | Daily | 7 days | CSI volume snapshots |
| Genesis files | Once (immutable) | Permanent | Git + off-cluster backup |
| Validator keys (Secrets) | On change | Permanent | Encrypted off-cluster backup |
| Contract addresses | On deploy | Permanent | Git + ConfigMap |
| Monitoring data | N/A (Prometheus retention) | 30 days default | Prometheus TSDB |
