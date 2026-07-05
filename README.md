# Hyperledger Besu Dual-Network Deployment

> Production-grade private + public Hyperledger Besu blockchain networks on Kubernetes,
> connected by an anchor bridge for transparency verification.

---

## Architecture

Two **genuinely separate** Besu blockchains running in the same Kubernetes cluster:

| | Private Network | Public Network |
|---|---|---|
| **Namespace** | `besu-private` | `besu-public` |
| **Chain ID** | `78901` | `78902` |
| **Purpose** | RIR consortium ledger (BGP route-origin registry) | Transparency/verification ledger (anchor records) |
| **Consensus** | QBFT (7 validators) | QBFT (5 validators) |
| **Membership** | Permissioned (onchain + local permissioning) | Open (any node can join) |
| **Exposure** | ClusterIP only (internal) | Ingress + LoadBalancer (internet-facing) |

Connected via **`bridge/anchor-service`** — a CronJob in `besu-app` namespace that reads private chain state and submits Merkle root anchors to the public chain every 10 minutes.

---

## Quick Start

```bash
# 1. Review and customize configuration
vi config.env

# 2. Apply Phase 1 foundation (namespaces + RBAC)
kubectl apply -f phase1-foundation/namespaces.yaml
kubectl apply -f phase1-foundation/rbac-private.yaml
kubectl apply -f phase1-foundation/rbac-public.yaml
kubectl apply -f phase1-foundation/rbac-app.yaml

# 3. Verify Phase 1
bash phase1-foundation/phase1-verify.sh

# 4. Run full deployment (Phases 2–9)
bash easy-setup/run.sh
```

---

## Directory Structure

The numbered-folder convention mirrors the reference project ([BGPHLF](https://github.com/majednitol/BGPHLF)), duplicated per network:

```
besu-network/
├── config.env                     # Single source of truth (both networks)
├── phase1-foundation/             # Phase 1: namespaces, RBAC, capacity plan, design docs
├── private-network/               # Phases 2–4: private permissioned chain
│   ├── 1.storage/                 # PV/PVC for validator data
│   ├── 2.genesis/                 # QBFT genesis + validator keys
│   ├── 3.configmap/               # genesis.json, static-nodes.json, permissions
│   ├── 3.5.tls/                   # Internal CA + per-node TLS certs
│   ├── 4.bootnodes/               # 2 bootnodes (ClusterIP only)
│   ├── 5.validators/              # 7 StatefulSets (one per org)
│   ├── 6.rpc-nodes/               # 6 RPC nodes (one per org, internal)
│   ├── 7.privacy/                 # Tessera (optional)
│   ├── 8.contracts/               # PrefixRegistry.sol + permissioning contracts
│   └── 9.network-policy/          # Default-deny + explicit allows
├── public-network/                # Phases 5–6: public open chain
│   ├── 1.storage/ → 6.rpc-nodes/ # Same structure, no permissioning
│   ├── 7.contracts/               # RegistryAnchor.sol
│   ├── 8.ingress/                 # Public HTTPS ingress
│   └── 9.network-policy/          # Allow internet, deny besu-private
├── bridge/                        # Phase 7: anchor-service CronJob
├── 10.api/                        # Phase 8: REST API + gobgp sidecar
├── 11.ui/                         # Phase 8: Frontend dashboard
├── 12.explorer/                   # Phase 8: Blockscout (private + public)
├── 13.monitoring/                 # Phase 9: Prometheus + Grafana
├── 14.ingress/                    # Phase 9: Top-level ingress aggregator
└── easy-setup/                    # Orchestration scripts
    ├── run-private.sh             # Phases 2–4
    ├── run-public.sh              # Phases 5–6
    ├── run-bridge.sh              # Phase 7
    └── run.sh                     # Full deployment (all phases)
```

---

## Phases

| Phase | Description | Script |
|-------|-------------|--------|
| 1 | Foundation, Governance & Capacity Planning | `phase1-foundation/` (manual) |
| 2 | Private Network: Genesis, Keys & Transport Security | `run-private.sh` steps 1–3.5 |
| 3 | Private Network: Nodes & Network Policy | `run-private.sh` steps 4–6, 9 |
| 4 | Private Network: Contracts & Privacy Layer | `private-network/8.contracts/` |
| 5 | Public Network: Genesis & Ingress TLS | `run-public.sh` steps 1–3, 8 |
| 6 | Public Network: Nodes, Autoscaling & Network Policy | `run-public.sh` steps 4–6, 9 |
| 7 | Bridge: Anchoring Contract & Relayer | `run-bridge.sh` |
| 8 | Application Layer, Explorers & API Auth | `10.api/`, `11.ui/`, `12.explorer/` |
| 9 | Observability, Logging & Security Hardening | `13.monitoring/`, `14.ingress/` |
| 10 | Backup/DR, Load Testing & Go-Live | Checklist + Caliper |

---

## Key Documents

| Document | Path |
|----------|------|
| Master Implementation Plan | `../besu-network-implementation-plan.md` |
| Capacity Plan | `phase1-foundation/capacity-plan.md` |
| Decision Log | `phase1-foundation/decisions.md` |
| API Design | `phase1-foundation/api-design.md` |
| Frontend Design | `phase1-foundation/frontend-design.md` |
| Phase 1 Verification | `phase1-foundation/phase1-verify.sh` |

---

## Organizations

| Org | Role | Private Validator | Private RPC |
|-----|------|-------------------|-------------|
| afrinic | African RIR | `validator-afrinic` | `rpc-afrinic` |
| apnic | Asia-Pacific RIR | `validator-apnic` | `rpc-apnic` |
| arin | North America RIR | `validator-arin` | `rpc-arin` |
| ripencc | Europe/Middle East RIR | `validator-ripencc` | `rpc-ripencc` |
| lacnic | Latin America RIR | `validator-lacnic` | `rpc-lacnic` |
| rono | Coordinator | `validator-rono` | `rpc-rono` |
