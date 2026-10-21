# The Sami Monetary Constitution — v1.0 (Final)

> **Status**: v1.0 Final — five rulings by Blue (2026-10-20, S.D. Day 26); legislative record in Appendix C
> **Date**: 2026-10-20 (S.D. Day 26)
> **Author**: Blue (CEO) direction + Xiaokui, scribe
> **Nature**: Authorizing statute of the Charter §8.9.3 amendment — anchoring obligations are governed by this Act; §8.9.3 has been amended (strikethrough preserved) to point here
> **Legislative origin**: The October 2026 ARTEX attacks on Japanese and South Korean financial institutions (fact layer in Appendix A)
> **In one line**: *Gentle living, iron-clad integrity, free witnessing — every entry of Sami's history, witnessed by the universe.*
> **Note**: This English version and the Chinese original (`sami-monetary-constitution-v1.0.md`) are both authoritative.

---

## Chapter 1 · Legislative Origin — The Lesson ARTEX Taught the World

From late September through October 2026, ARTEX — a Chinese open-source AI penetration-testing tool — was abused by hackers in successive attacks against South Korean (late Sept–early Oct; disclosed by CrowdStrike on Oct 7; at least 7 financial firms confirmed data breaches) and Japanese (investigated by GMO Internet Group, reported Oct 19; roughly 20–80 companies targeted) financial, retail, logistics, and e-commerce businesses.

What this wave of breaches exposed was not "not enough locks on the doors" — but something more fundamental: **after the fact, no one could prove which data had been altered and which had not.**

SemiDAO has treated evidence chains as a charter-level obligation from day one (§8.8 three-layer evidence architecture, §8.9.3 Merkle anchoring commitment, §8.10 integrity penalties). This Act elevates that obligation into the **monetary integrity law** of Sami: using free Bitcoin OpenTimestamps anchoring, tampering with history becomes computationally infeasible — and **anyone can verify it independently, trusting no one**.

---

## Chapter 2 · Constitutional Principles (Four)

### 2.1 The Integrity Principle (every change leaves a trace)

The Sami ledger (semidao-ledger) and all economic computation upon it take cryptographic integrity as their first line of defense. Any bit, any balance snapshot, any governance resolution — once anchored, any subsequent tampering **can necessarily be detected** — not by promise, but by the physical facts of sha256 and Bitcoin proof-of-work.

### 2.2 The Free Witness Principle (Trust no one, pay no one)

Anchoring uses OpenTimestamps (OTS): only hashes are written into Bitcoin OP_RETURN — **no trusted-third-party fees, no new trusted parties**. The cost of witnessing is zero, the cost of verifying is zero, and the need for trust is zero. This is isomorphic to SemiDAO's "Trust no one" data-sovereignty posture (the Golden Key principle).

### 2.3 The Independent Verifiability Principle (ask no one)

Any holder, any regulator, any external auditor may — **without SemiDAO's permission, and without depending on SemiDAO's survival** — independently verify any span of ledger history with a Bitcoin full node and OTS proof files. If SemiDAO disappears, the witness remains.

### 2.4 The Honest Boundary Principle (constitutional self-limitation)

This Act **claims proof of integrity only, and expressly disclaims the following three** — self-limited in writing, so no red team can pierce it:

| What we do NOT claim | Why |
|---|---|
| Confidentiality | An OTS-anchored hash ≠ encryption. Personal data or balances being *read* and exfiltrated cannot be prevented by this Act — that is the job of locks (encryption, access control) |
| Pre-anchor authenticity | Anchor garbage, and you have anchored garbage. OTS proves "unchanged since time T," not "correct before T" — pre-anchor truth is guarded by the §8.8 evidence architecture and §8.10 integrity penalties |
| Attribution | Proving data changed does not prove who changed it — that is the job of the signature layer (PQC/ML-DSA; migration tracks already laid out in the Knowledge Sovereignty Alignment) |

> One-line version: **OTS is "the honest ledger after the incident," not "the lock before it."** This boundary must be stated clearly when selling to anyone — including financial institutions. Honest self-limitation is more persuasive than omnipotent claims.

---

## Chapter 3 · The Anchoring System (Articles)

### 3.1 The three-tier anchoring ladder

| Tier | Object | Frequency | Tool | Status |
|---|---|---|---|---|
| **L1 Milestone anchor (tree-ring mode)** | Governance documents, charters, major bits, repo HEAD SHA | At milestones | OTS file/directory stamp | ✅ Operational (4 files on Oct 2; tree-ring snapshots Oct 3 & Oct 10; this Act v1.0 stamped upon finalization) |
| **L2 Periodic anchor (Epoch anchor)** | Merkle root of the full semidao-ledger | **Daily target** (ruled by Blue, 2026-10-20) | OTS + Merkle | Interim cadence until automated (§3.2 transitional clause) |
| **L3 High-frequency anchor (anti-revert anchor)** | Merkle root of transaction batches / balance snapshots | Per batch, after Contract Layer Phase 4 | OTS batch stamp | Future engineering — defends against the "alter one entry, then revert it" frame-skip attack; cost analysis in Appendix B |

### 3.2 The Epoch system (L2 articles)

1. The anchoring agent computes the Merkle root of all ledger bits at each daily epoch (UTC 00:00, i.e. 08:00 Taipei) and stamps it onto Bitcoin via `ots stamp`. **Transitional clause until automation is live**: anchor at a feasible periodic cadence (at least once per S.D. week); each anchor covers all bits in between — the interim does not lower the honesty standard, it only truthfully marks the granularity
2. The Merkle root and bit range (first–last serial numbers) are recorded in the anchoring status file — **the "no fresh data, no counting" iron rule** (§8.8.4): ranges must be recomputed from the ledger's raw data at the moment of anchoring; incrementing past agents' output is forbidden
3. Under Bitcoin congestion, confirmation may take 24–48 hours; the anchoring agent tracks via watchdog mode until `ots upgrade` completes, and reports the proof (the battle-tested Oct 10 batch pattern). The anchoring moment is the stamp submission time; confirmation delay does not weaken the proof
4. Within 24 hours after each Epoch anchor completes, run a full `ots verify` — **stamped is not anchored; verified is.** Only upon verification is the obligation discharged

### 3.3 The integrity precondition for monetary computation (ties back to §8.9)

The §8.9 two-layer structure: bits are chronicle (uncapped); Sami is economy (with policy). This article adds: **all issuance, distribution, and forfeiture computations for Sami may be based only on bit ranges already covered by L2 or higher anchoring.** Bits in unanchored ranges may enter the ledger (the chronicle waits for no one) but must not enter economic computation — **anchoring is the coming-of-age of the economy.**

### 3.4 The constitutional procedure for tampering incidents (ties back to §8.10)

When any independent verifier finds the ledger inconsistent with the Bitcoin witness:

1. The inconsistency itself immediately enters the ledger (honesty culture: errors enter history)
2. The §8.10 integrity-penalty procedure is triggered (evidence chain = OTS proof files, computationally undeniable)
3. Right-to-know of the affected (§3.5): all holders are informed within a reasonable time — **if you did something that affects your neighbors, knock on their doors**

---

## Chapter 4 · External Chartering (Financial-Sector Clause — ruled by Blue 2026-10-20: stays in the constitution)

The pain point of the ARTEX disaster is the financial sector's pain point. SemiDAO's anchoring infrastructure (OTS pipeline + constitutional procedure) is opened externally as a **public-good service**:

- **Positioning**: not a cybersecurity product, but "the honest ledger after the incident" — enabling a financial institution, within 24 hours of a breach, to present undeniable evidence to regulators, customers, and courts of "which data was in what state, at what time"
- **External claim boundary** (sales iron rule): defenses (encryption / access control / penetration testing) still must be built; we sell the evidence chain, not the lock. No external claim may exceed the §2.4 three disclaimers
- **The free principle**: Bitcoin anchoring itself costs nothing; SemiDAO charges for engineering and governance procedure (Honest Witness as a Service — pricing and contract form to be set by the then-current governance process; this Act does not presuppose them)

> Honest note: this chapter is directional; the concrete business model is undecided and constitutes no external commitment.

---

## Appendix A · ARTEX Incident Fact Layer (three-tier citation separation)

**Verified (cross-checked against reputable second-hand sources)**:
- Korea line: CrowdStrike disclosure, 2026-10-07 — attackers used ARTEX, a Chinese open-source AI penetration-testing tool (capable of calling Claude/GPT/DeepSeek and other LLMs; primary backend DeepSeek v4.1-flash) against South Korean financial institutions; as of Oct 5, Korean media counted 7 financial firms with confirmed data leaks (sources: iThome 2026-10-08, ithome.com.tw/news/179506; fox.hsiao compilation 2026-10-16)
- Japan line: GMO Internet Group / GMO Cybersecurity by Ierae investigation, 2026-10-19 — 6 servers dedicated to Japan, targeting ~20–80 companies across finance/retail/logistics/e-commerce (sources: Nownews and other Chinese-language reports)
- South Korean President Lee Jae-myung ordered a thorough investigation and a review of national core systems (source: Yonhap, via Threads relay)

**Verification boundary (honest declaration)**:
- "Japan's cumulative personal-data leaks this year exceed 180 million" — from an AI-aggregator app screenshot; **primary source not located**; this Act does not cite this figure as legislative fact
- CrowdStrike assesses "Chinese-speaking attacker / financial motive" with only medium confidence and attributes no named organization — this Act makes no motive or nationality attribution

**Our reading (not fact)**: "After the fact, no one can prove the data was untouched" is the structural gap this incident exposed — this is SemiDAO's interpretive frame, not any investigating body's conclusion.

---

## Appendix B · L3 Scaling Cost Analysis (ruled by Blue 2026-10-20 to include)

> **Conclusion first: cost does not grow with entry count — one tree collects all.**

**The anchoring method**: 100 million entries are not 100 million on-chain transactions; the 100 million fingerprints (sha256) are first computed **locally** into a single Merkle root, and only the 32-byte root goes on-chain (1 OP_RETURN transaction).

| Item | Figure (100M entries/day scenario) | Notes |
|---|---|---|
| Local Merkle computation | ~10 seconds | Tree height log₂(10⁸)≈27 levels → ~200M sha256 ops; seconds-to-tens-of-seconds on Apple Silicon. **Zero cost, pure local compute** |
| On-chain transactions | **1 per day** | OP_RETURN holds only the root; transaction ~150 vB |
| Daily cost | **~$1–3** (self-paid) / **$0** (OTS public pool) | 2026 observed fee rates 2–17 sat/vB |
| Annual cost | ~$400–1,000 (self-paid) / $0 (OTS pool) | |

**The real costs move to two places — not on-chain:**

1. **Proof-file storage**: an individual proof = 27-level path × 32B ≈ 1KB/entry. Storing all 100M ≈ 100 GB/day — in practice, **generated on demand** (a path is expanded only when someone needs to verify that entry); full storage is unnecessary
2. **Time-granularity upcharge**: hourly anchoring ×24 ≈ $25–75/day; per-block anchoring ×144 ≈ $150–400/day. Once a day is priced as once a day — **100M entries cost the same as 1,000**

**The contrast case (honest boundary)**: naively putting 100M entries on-chain individually — the **entire** Bitcoin network processes only ~600–700K transactions per day. 100M entries is not expensive; it is **physically impossible**. Merkle is the only solution — which is exactly why Satoshi wrote Merkle trees into Bitcoin's block structure. SemiDAO borrows Bitcoin's own skeleton to scale.

> One-line version: **100M entries/day ≈ the price of a daily cup of coffee (self-paid) or $0 (OTS pool); the cost of scaling lives in local CPUs and disks, not on-chain.** This is the mathematical foundation that lets §3.3's "anchoring is the coming-of-age of the economy" upgrade painlessly to L3.

---

## Appendix C · Legislative Record (five rulings by Blue, 2026-10-20)

| # | Question | Ruling |
|---|---|---|
| 1 | Placement | **Amend** — Charter §8.9.3 amended in place (strikethrough history preserved); no new §8.11 |
| 2 | Epoch frequency | **Daily as target** — ruled after the cost Q&A ($0–3/day, Appendix B) |
| 3 | Naming | **Confirmed** — SemiDAO is the organization; Sami is the currency |
| 4 | Chapter 4 external clause | **Stays in the constitution** (directional clause; honestly marked as no external commitment) |
| 5 | The document itself | **All approaches approved** — OTS anchoring + bilingual versions + into the repo |

**Minting**: bit-000012 (hash chain continued); evidence: this Act's original + the Charter §8.9.3 amendment diff + the Discord legislative thread.

---

## Appendix D · Legislative Wiring Diagram

```
§8.8 three-layer evidence architecture (where evidence comes from)
   ↓
§8.9 two-layer currency (bits as chronicle × Sami as economy) ←— this Act §3.3 adds: economic computation only consumes anchored ranges
   ↓
§8.9.3 Merkle anchoring (formerly "monthly") ←— amended 2026-10-20: daily Epoch anchor (L2) + L3 high-frequency track (this Act §3.1/3.2)
   ↓
§8.10 integrity penalties ←— this Act §3.4 adds: OTS-inconsistency evidence as computationally undeniable trigger evidence
```
