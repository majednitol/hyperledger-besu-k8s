# Phase 1 — Decision Log

> Tracks all architectural decisions made during the Besu dual-network design and implementation.
> Each decision records what was decided, what alternatives were considered, and why this option was chosen.

---

## Architectural Decisions

### D1: Two Separate Besu Chains (not two RPC tiers)

| | |
|---|---|
| **Decision** | Run two genuinely independent Besu blockchains — private (permissioned) and public (open) — with separate genesis, chain IDs, validator sets, and Kubernetes namespaces |
| **Alternatives** | (a) Single chain with permissioned vs public RPC exposure tiers; (b) Single chain with application-level access control |
| **Rationale** | v1 of the plan incorrectly modeled this as two tiers of one chain. Two separate chains provide genuine membership separation, independent consensus parameters, and true isolation. The bridge connects them at the application level without protocol-level coupling. |
| **Date** | 2026-07-05 |

### D2: QBFT Consensus for Both Chains

| | |
|---|---|
| **Decision** | Use QBFT (Quorum Byzantine Fault Tolerant) consensus on both private and public networks |
| **Alternatives** | (a) IBFT2; (b) Clique (PoA); (c) Ethash (PoW); (d) Different consensus per network |
| **Rationale** | QBFT is Besu's production-recommended BFT consensus algorithm. Same algorithm on both chains simplifies operations, monitoring, and operator training. QBFT provides immediate finality which is important for the registry use case. |
| **Date** | 2026-07-05 |

### D3: 7 Private Validators (one per org)

| | |
|---|---|
| **Decision** | Run 7 validators on the private network — one per RIR organization (afrinic, apnic, arin, ripencc, lacnic) plus the rono coordinator |
| **Alternatives** | (a) 4 validators (minimum BFT); (b) 5 validators; (c) 6 validators (one per RIR, no coordinator) |
| **Rationale** | Maps 1:1 to the RIR consortium membership. 7 validators gives `⌊(7-1)/3⌋ = 2` fault tolerance, which is a comfortable margin for maintenance operations. Each org operates its own validator for sovereignty. |
| **Date** | 2026-07-05 |

### D4: 5 Public Validators (consortium-seeded)

| | |
|---|---|
| **Decision** | Seed the public network with 5 consortium-operated validators, with a documented governance process for adding external sealers |
| **Alternatives** | (a) 3 validators (minimum for any BFT); (b) 4 validators; (c) 7 validators (matching private) |
| **Rationale** | 5 gives `⌊(5-1)/3⌋ = 1` fault tolerance. This is a tighter margin than private but acceptable for a transparency chain where consensus liveness is less critical than the private registry. The governance process for adding external validators is documented as a manual runbook for v1. |
| **Date** | 2026-07-05 |
| **Risk** | Only 1 fault tolerated — maintenance window is extremely constrained. Monitor and potentially increase to 7 after go-live. |

### D5: Pod Security Admission: `restricted`

| | |
|---|---|
| **Decision** | Apply `pod-security.kubernetes.io/enforce: restricted` label to all three namespaces |
| **Alternatives** | (a) `baseline` (less restrictive); (b) `privileged` (no restrictions); (c) No PSA labels (convention-only) |
| **Rationale** | `restricted` is the strongest PSA level. It enforces `runAsNonRoot`, drops all capabilities, and prevents privilege escalation at the cluster level — not just in code review. Without this, the securityContext settings throughout the manifests are conventions that a future PR could quietly remove. |
| **Date** | 2026-07-05 |

### D6: Namespace-Scoped RBAC (no cluster-admin)

| | |
|---|---|
| **Decision** | Three separate `Role`/`RoleBinding` pairs — one per namespace — with least-privilege verbs. No CI/CD service account gets `cluster-admin`. |
| **Alternatives** | (a) Single shared `ClusterRole` for all operators; (b) `cluster-admin` for the team |
| **Rationale** | Namespace-scoped roles prevent accidental cross-namespace damage. Private network operators can't touch public network resources and vice versa. Secret writes are excluded from all operational roles — key rotation uses a separate, audited break-glass path. |
| **Date** | 2026-07-05 |

### D7: Bridge via CronJob Anchor (not direct P2P)

| | |
|---|---|
| **Decision** | Connect private and public networks via an application-level bridge — a CronJob that reads private chain state and submits Merkle root anchors to the public chain every 10 minutes |
| **Alternatives** | (a) Direct P2P peering between chains; (b) Manual anchor submission; (c) Real-time event relay; (d) No bridge (independent chains) |
| **Rationale** | Application-level bridge is the simplest pattern with no protocol-level coupling. CronJob provides controllable, auditable frequency. The bridge pod is the ONLY workload with network access to both namespaces, and its relayer key can only call one function (`submitAnchor`) on one contract. |
| **Date** | 2026-07-05 |

### D8: Image Pinning Strategy

| | |
|---|---|
| **Decision** | Use Besu image tagged by version (`24.12.2`) during Phase 1–2 development; migrate to digest pinning before Phase 3 (production nodes) |
| **Alternatives** | (a) Always use digest from day 1; (b) Always use `:latest`; (c) Use tag only |
| **Rationale** | Pragmatic balance: tags provide development velocity during early phases; digest pinning provides production immutability and supply-chain security for the running network. The TODO in `config.env` explicitly tracks this migration. |
| **Date** | 2026-07-05 |

---

## Infrastructure Decisions (pending user confirmation)

| # | Decision | Status | Notes |
|---|----------|--------|-------|
| D9 | Secrets backend: K8s native Secrets | ⚠️ Assumed | User to confirm or specify cloud-native alternative |
| D10 | Tessera: not needed for v1 | ⚠️ Assumed | User to confirm |
| D11 | Target cloud/cluster provider | ❓ Open | Affects LoadBalancer implementation, storage class, multi-AZ |
| D12 | Container registry for custom images | ❓ Open | Needed for anchor-service, API, UI images |
