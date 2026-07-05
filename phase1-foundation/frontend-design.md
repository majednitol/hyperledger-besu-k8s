# Frontend/UI Design Direction — Phase 1 Design Decision

> Locks in the aesthetic direction, design tokens, and component strategy for the `11.ui` layer.
> Implemented in Phase 8; documented here so all teams align on visual language.

---

## Design Direction

### Aesthetic: Industrial Utilitarian

A NOC-dashboard-inspired interface that reflects the infrastructure and networking domain
(BGP routing, RIR operations, blockchain consensus). Think control rooms, terminal output,
and data-dense monitoring screens — not SaaS marketing pages.

**Why this direction**:
- Matches the mental model of the target users (network engineers, RIR operators)
- Data-dense layouts are functional, not decorative — every element serves an operational purpose
- Dark mode by default reduces eye strain for operators monitoring 24/7
- Terminal-inspired typography signals technical credibility

### DFII Score: 15 (Excellent — Execute Fully)

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Aesthetic Impact | 4/5 | Distinctive for blockchain/networking — avoids generic "crypto dashboard" patterns |
| Context Fit | 5/5 | Perfect match for infrastructure operators and RIR admin teams |
| Implementation Feasibility | 4/5 | Standard web tech — no exotic rendering requirements |
| Performance Safety | 4/5 | Data-heavy but paginated; real-time updates scoped to status bar only |
| Consistency Risk | 2/5 | Well-constrained design system with few custom components |
| **DFII** | **(4+5+4+4) - 2 = 15** | |

---

## Differentiation Anchor

> "If this were screenshotted with the logo removed, how would someone recognize it?"

**The Dual-Chain Status Header**: A persistent, always-visible bar across the top of every page showing:
- Private chain: block height, validator count, last block time
- Public chain: block height, peer count, last block time
- Bridge: last anchor age, anchor status (healthy/stale/failed)

This header makes the two-network architecture **tangible** — users always see both chains
and the bridge that connects them. No other blockchain dashboard does this because none
operate two chains with a bridge.

---

## Design System Tokens

### Typography

| Token | Value | Usage |
|-------|-------|-------|
| `--font-display` | `'JetBrains Mono', 'Fira Code', monospace` | Headings, data values, hash displays |
| `--font-body` | `'IBM Plex Sans', 'Inter', sans-serif` | Body text, labels, descriptions |
| `--font-size-xs` | `0.75rem` (12px) | Metadata, timestamps |
| `--font-size-sm` | `0.875rem` (14px) | Table content, form labels |
| `--font-size-base` | `1rem` (16px) | Body text |
| `--font-size-lg` | `1.25rem` (20px) | Section headers |
| `--font-size-xl` | `1.5rem` (24px) | Page titles |
| `--font-size-2xl` | `2rem` (32px) | Hero numbers (block height, TPS) |

**Rationale**: JetBrains Mono's monospace design is native to the developer/operator context.
IBM Plex Sans (IBM's design heritage) reinforces the industrial aesthetic without
being as overused as Inter or Roboto.

### Color Palette

| Token | HSL | Hex | Usage |
|-------|-----|-----|-------|
| `--color-bg-primary` | `hsl(210, 15%, 10%)` | `#151a1e` | Page background |
| `--color-bg-surface` | `hsl(210, 12%, 16%)` | `#232930` | Card/panel backgrounds |
| `--color-bg-elevated` | `hsl(210, 10%, 22%)` | `#323940` | Hover states, active panels |
| `--color-text-primary` | `hsl(210, 10%, 90%)` | `#e1e4e8` | Primary text |
| `--color-text-secondary` | `hsl(210, 8%, 60%)` | `#8d9199` | Secondary text, labels |
| `--color-text-muted` | `hsl(210, 6%, 40%)` | `#5c6168` | Tertiary text, metadata |
| `--color-accent-green` | `hsl(150, 70%, 45%)` | `#22c55e` | Healthy status, validated records |
| `--color-accent-amber` | `hsl(35, 90%, 55%)` | `#f59e0b` | Warning states, pending records |
| `--color-accent-red` | `hsl(0, 75%, 55%)` | `#dc2626` | Error states, revoked records |
| `--color-accent-blue` | `hsl(210, 80%, 55%)` | `#3b82f6` | Links, interactive elements |
| `--color-border` | `hsl(210, 10%, 25%)` | `#383e45` | Subtle borders |
| `--color-private-chain` | `hsl(260, 60%, 55%)` | `#8b5cf6` | Private chain indicator |
| `--color-public-chain` | `hsl(180, 60%, 45%)` | `#14b8a6` | Public chain indicator |

**Rationale**: Near-black blue base with terminal green accents. The private/public chain
colors (purple/teal) are semantically distinct and visible against dark backgrounds.

### Spacing

| Token | Value | Usage |
|-------|-------|-------|
| `--space-unit` | `4px` | Base unit |
| `--space-xs` | `4px` | Inline padding, tight groups |
| `--space-sm` | `8px` | Component internal padding |
| `--space-md` | `16px` | Component margins, card padding |
| `--space-lg` | `24px` | Section spacing |
| `--space-xl` | `32px` | Page section gaps |
| `--space-2xl` | `48px` | Major layout divisions |

### Motion

| Property | Value | Usage |
|----------|-------|-------|
| `--transition-fast` | `100ms ease-out` | Hover states, button feedback |
| `--transition-normal` | `200ms ease-out` | Panel expand/collapse |
| `--transition-slow` | `400ms ease-in-out` | Page transitions |
| `--pulse-interval` | `2s` | Status bar live indicator |

**Motion philosophy**: Minimal — data transitions only. No decorative animation.
The only persistent animation is a subtle pulse on the status bar's live-data indicator.

### Border Radius

| Token | Value | Usage |
|-------|-------|-------|
| `--radius-sm` | `4px` | Buttons, inputs |
| `--radius-md` | `8px` | Cards, panels |
| `--radius-lg` | `12px` | Modal dialogs |
| `--radius-full` | `9999px` | Status badges |

---

## Key Components (Phase 8 implementation targets)

### 1. Dual-Chain Status Header
- Persistent top bar (48px height)
- Left: Private chain status (purple indicator)
- Center: Bridge status (green/amber/red pulse)
- Right: Public chain status (teal indicator)
- Updates via WebSocket or polling (5s interval)

### 2. Record Submission Form
- Prefix input with CIDR validation
- ASN input with range validation
- Org identity auto-detected from auth context
- Submit → loading → confirmation with tx hash

### 3. Record List / Table
- Dense data table with sort/filter
- Status column with color-coded badges (Pending=amber, Validated=green, Revoked=red)
- Inline expansion for record details
- Pagination controls

### 4. Anchor Timeline
- Chronological list of bridge anchors
- Shows merkle root, private block number, public tx hash, age
- "Verify" button per anchor

### 5. Network Dashboard
- Private chain: validator grid (7 nodes), block height, consensus round info
- Public chain: validator grid (5 nodes), peer count, block height
- Bridge: anchor history chart, success rate, last anchor age

---

## Anti-Patterns to Avoid

❌ Generic SaaS dashboard templates (Tailwind UI / ShadCN defaults)
❌ Purple-on-white crypto gradients
❌ System fonts (Inter, Roboto, Arial)
❌ Decorative micro-animations without purpose
❌ Symmetrical, predictable card grids
❌ Light mode as default (operators work in dark environments)

✅ Data density over whitespace
✅ Monospace for all hash/address/number displays
✅ Color-coding that maps to operational states
✅ Every visual element serves an operational purpose
