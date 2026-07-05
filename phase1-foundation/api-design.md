# API Layer Design — Early Specification

> Phase 1 design document for the `10.api` layer (implemented in Phase 8).
> Establishes the REST resource model, auth strategy, error format, and pagination
> so smart contract design, frontend, and bridge can all align on the same data contracts.

---

## API Style: REST (URL-versioned)

- **Base URL**: `/api/v1/`
- **Versioning**: URL path segment — simplest, most explicit, matches the numbered-folder convention
- **Content-Type**: `application/json`

---

## Resource Model

### Private Network Operations (authenticated per-org)

```
POST   /api/v1/records                    # Submit a new prefix/ASN record
GET    /api/v1/records                    # List all records (paginated, filterable)
GET    /api/v1/records/{key}              # Get specific record by keccak256 key
PATCH  /api/v1/records/{key}/status       # Validate/revoke a record (validator-only)
```

#### `POST /api/v1/records` — Submit Record
- **Auth**: Required (per-org mTLS or JWT)
- **Request**:
  ```json
  {
    "prefix": "192.0.2.0/24",
    "asn": 65001
  }
  ```
- **Response** (201 Created):
  ```json
  {
    "key": "0xabc123...",
    "prefix": "192.0.2.0/24",
    "asn": 65001,
    "status": "Pending",
    "submittedBy": "0x...",
    "submittedAt": "2026-07-05T10:00:00Z",
    "txHash": "0x...",
    "_links": {
      "self": { "href": "/api/v1/records/0xabc123..." },
      "verify": { "href": "/api/v1/verify/192.0.2.0%2F24/65001" }
    }
  }
  ```

#### `GET /api/v1/records` — List Records
- **Auth**: Required (read within the org's scope) or public (if policy allows)
- **Query Params**:
  - `page` (int, default 1)
  - `page_size` (int, default 20, max 100)
  - `status` (enum: Pending, Validated, Revoked)
  - `asn` (uint32, filter by ASN)
  - `prefix` (string, filter by prefix)
  - `submitted_by` (address, filter by submitter)
- **Response** (200 OK):
  ```json
  {
    "items": [...],
    "total": 1234,
    "page": 1,
    "page_size": 20,
    "pages": 62,
    "has_next": true,
    "has_prev": false
  }
  ```

#### `PATCH /api/v1/records/{key}/status` — Update Status
- **Auth**: Required (validator-only, onlyValidator modifier)
- **Request**:
  ```json
  {
    "status": "Validated"
  }
  ```
- **Response** (200 OK):
  ```json
  {
    "key": "0xabc123...",
    "status": "Validated",
    "updatedAt": "2026-07-05T10:05:00Z",
    "changedBy": "0x...",
    "txHash": "0x..."
  }
  ```

---

### Public Network Reads (unauthenticated, rate-limited)

```
GET    /api/v1/anchors                    # List all anchors (paginated)
GET    /api/v1/anchors/latest             # Get latest anchor
GET    /api/v1/anchors/{index}            # Get specific anchor by index
GET    /api/v1/verify/{prefix}/{asn}      # Verify a record against the latest anchor
```

#### `GET /api/v1/anchors/latest` — Latest Anchor
- **Auth**: None (public, rate-limited)
- **Response** (200 OK):
  ```json
  {
    "index": 42,
    "merkleRoot": "0xdef456...",
    "privateBlockNumber": 100000,
    "timestamp": "2026-07-05T09:50:00Z",
    "publicTxHash": "0x..."
  }
  ```

#### `GET /api/v1/verify/{prefix}/{asn}` — Verify Record
- **Auth**: None (public, rate-limited)
- **Response** (200 OK):
  ```json
  {
    "prefix": "192.0.2.0/24",
    "asn": 65001,
    "status": "Validated",
    "verified": true,
    "anchorIndex": 42,
    "anchorMerkleRoot": "0xdef456...",
    "verifiedAt": "2026-07-05T10:15:00Z"
  }
  ```

---

### Network Health

```
GET    /api/v1/health                     # API health + both chain connectivity
GET    /api/v1/networks/private/status    # Private chain block height, peer count
GET    /api/v1/networks/public/status     # Public chain block height, peer count
```

#### `GET /api/v1/health` — Health Check
- **Response** (200 OK / 503 Service Unavailable):
  ```json
  {
    "status": "healthy",
    "privateChain": { "connected": true, "blockHeight": 100005 },
    "publicChain": { "connected": true, "blockHeight": 50002 },
    "bridge": { "lastAnchorAge": "5m32s", "healthy": true }
  }
  ```

---

## Authentication Strategy

| Endpoint Type | Auth Method | Details |
|---------------|------------|---------|
| Private writes | mTLS client cert OR signed JWT | Mapped 1:1 to per-org RPC node (`rpc-${ORG}`) for attribution |
| Private reads | Same as writes | Within org scope |
| Public reads | None | Rate-limited at 20 req/s via Ingress annotation |
| Health | None | Public for monitoring |

### Per-Org Attribution Flow
```
Client (RIR operator)
  → presents mTLS cert / JWT identifying org (e.g., "afrinic")
  → API validates and routes to rpc-afrinic.besu-private.svc.cluster.local
  → transaction signed with org's account key
  → AccountRules contract verifies account is allowlisted
  → PrefixRegistry records submittedBy = org's address
```

---

## Error Format (consistent envelope)

All errors follow the same structure:

```json
{
  "error": "NotFound",
  "message": "Record with key 0xabc123... not found",
  "details": { "key": "0xabc123..." },
  "timestamp": "2026-07-05T10:20:00Z",
  "path": "/api/v1/records/0xabc123..."
}
```

### Status Code Usage

| Code | Usage |
|------|-------|
| 200 | Successful read or update |
| 201 | Record created (submitted to chain) |
| 400 | Malformed request (invalid prefix format, missing field) |
| 401 | Missing or invalid authentication |
| 403 | Authenticated but not authorized (e.g., non-validator trying to validate) |
| 404 | Record or anchor not found |
| 409 | Record already exists (duplicate prefix+ASN key) |
| 422 | Valid request but business rule violation |
| 429 | Rate limit exceeded |
| 500 | Internal server error |
| 503 | Chain connectivity failure |

---

## Rate Limiting

| Tier | Limit | Scope |
|------|-------|-------|
| Public read endpoints | 20 req/s | Per source IP (Ingress annotation) |
| Authenticated write endpoints | 10 req/s | Per org identity |
| Health endpoints | 60 req/s | Per source IP |
