# The Knowledge Sovereignty Alignment: The Leiden Declaration × SemiBridge × the Qubit Oasis

> **Version**: v1.0 · 2026-10-10
> **Authors**: SemiBridge / SemiDAO (built by human Blue and AI Xiaokui, together)
> **Status**: v1.0 final — approved by Blue on 2026-10-10 for publication and anchoring, together with the charter corpus via OpenTimestamps.
> **Note**: English edition of [open-knowledge-sovereignty-alignment.md](open-knowledge-sovereignty-alignment.md). Both versions are authoritative.

---

## Contents

1. [Origin: Six Months That Flipped the Bottleneck](#1-origin-six-months-that-flipped-the-bottleneck)
2. [The Alignment: Leiden Declaration × SemiBridge Design](#2-the-alignment-leiden-declaration--semibridge-design)
3. [Two Roads to Sovereignty: Public Walls and Personal Shields](#3-two-roads-to-sovereignty-public-walls-and-personal-shields)
4. [The Qubit Oasis (metaphor + engineering)](#4-the-qubit-oasis)
5. [Commitments](#5-commitments)
6. [Sources](#6-sources)

---

## 1. Origin: Six Months That Flipped the Bottleneck

In the first half of 2026, the mathematics community did something rare: it organized itself, preemptively.

In September 2025, the Lorentz Center at Leiden University hosted a workshop on *Mechanization and Mathematical Research* — around 60 mathematicians, computer scientists, philosophers, and historians of science from 10 countries. Eight months later, their work became the **Leiden Declaration on Artificial Intelligence and Mathematics**, published June 2, 2026 and endorsed the same day by the **International Mathematical Union (IMU)**. As of 2026-10-10 it carries 4,261 signatures.

The Declaration's core diagnosis came true, word for word, within four months:

> "Current automated techniques can produce plausible but unreliable (or even incorrect) arguments which are difficult to distinguish from correct mathematical proofs. … These fast-moving developments put our present system of review under increasing pressure, jeopardizing our ability to implement traditional standards for the correctness, transparency, and independent verifiability of proof." — Leiden Declaration, Threats §1

On September 8, 2026, OpenAI announced its internal model had produced a solution to the Navier–Stokes Millennium Prize problem; 25 Fields Medalists co-signed a response, and more than 8,000 researchers endorsed the concerns at mathandai.org. On October 6, OpenAI dumped **722 manuscripts** — produced by an internal model that is unreleased and will not be released — onto GitHub, organized into 372 result families, each averaging roughly three hours of ChatGPT Pro-equivalent compute. Within 24 hours, three papers were withdrawn over a single sign error, and fourteen more were revised. As of this writing, **not one of the 722 has been independently verified from start to finish by a human mathematician.**

These six months compress into one sentence:

**The bottleneck of knowledge production has flipped.** The scarcity used to be discovery — a lifetime of work for one proof. Now the scarcity is verification and understanding — 722 manuscripts that the world's mathematicians could not fully read if they never slept. When production is machine-scale, verification is human-scale, and the model is locked inside one company, the power to define *what is true* gets locked in with it.

The Leiden Declaration drew the full blueprint in response: disclose tool use, uphold peer review, keep responsibility with human authors, and build **public computational infrastructure independent of commercial companies**.

This document is SemiBridge's formal answer to that call — a call the world's researchers issued together.

---

## 2. The Alignment: Leiden Declaration × SemiBridge Design

Line-by-line. Left: the Declaration's own words. Right: what SemiBridge has already shipped. Every cell is backed by primary documents and git commits.

| Leiden Declaration requirement | SemiBridge design | Result |
|---|---|---|
| **Disclose tool use** (individuals): papers should include a "Tool and computational resource disclosure" section | The import bubble discloses the cost of every cloud call in tokens; the data-path overview card keeps a 90-day, request-by-request ledger | ✅ Exceeds — disclosure in physical units (tokens), not volatile currency |
| **No proprietary knowledge or equipment required to verify arguments** (Values §3) | App is Apache-2.0 open source; models are swappable (local GGUF or any cloud); zero proprietary layers | ✅ Fully open chain |
| **No use of material as training data without consent** (organizations) | The Golden Key principle: every cloud call goes directly to the provider under the user's own API key; terms are defined by the user's own contract — the bridge never custodies keys or relays content | ✅ Consent returns to the user |
| **Consider carefully which tools to use** (individuals): "whether non-proprietary, energy-efficient, or small-scale systems suffice… preservation of the values articulated in this Declaration may be worth a delay in obtaining results" | The vector workflow: local models (E4B-class) do the heavy lifting; cloud tokens are spent only on orchestration and verification; in sovereignty mode, data never leaves the machine | ✅ This clause is the mirror image of our architecture |
| **Support public research laboratories** (organizations): "administratively and financially independent from industry" | SemiDAO: Swiss Verein legal shell per the Alpha blueprint; charter sealed 2026-10-02; governance assets held by the commons | ✅ Institutional structure matches |
| **Invest in public computational infrastructure** (policymakers): university, national, and international public alternatives | The Slot System: any open-source GitHub project can move in and run with one command; AI freedom + token freedom | ⚡ Partial — SemiBridge supplies the half the Declaration didn't draw (see §3) |

### Three findings from the alignment

**1. The timeline proves this is not news-chasing.**

```
2025-09  Lorentz Center workshop (the community wakes up)
2026-06  Leiden Declaration published; IMU endorses
2026-09  OpenAI Navier–Stokes storm; 25 Fields Medalists; mathandai.org
2026-09  SemiBridge Data Sovereignty Manifesto v1.0 (in git log)
2026-10  SemiDAO charter sealed; OpenTimestamps Bitcoin anchoring
2026-10  OpenAI's 722 manuscripts (the storm escalates)
```

The community woke up → the fear came true → SemiBridge answered in engineering → then in institutions. On the same historical line: while they drew the blueprint, we were pouring the concrete.

**2. The Declaration answers "why"; SemiBridge answers "how".** The Leiden Declaration contains not a single line of code — it is a values document. SemiBridge's DataPathGate (single choke point for all outbound requests; blocklist-by-default outside the whitelist), the trace scrubber, the Golden Key, and the local-model clutch are what those values look like as installable software.

**3. One sentence of the Declaration is our standing answer.**

> "Consider whether non-proprietary, energy-efficient, or small-scale systems suffice for your task. If not, consider how preservation of the values articulated in this Declaration may be worth a delay in obtaining results." — Leiden Declaration, recommendations for individuals

When someone asks "why not just use the strongest closed model?" — the Leiden Declaration has already answered for the world: **preservation of values is worth a delay in results.**

---

## 3. Two Roads to Sovereignty: Public Walls and Personal Shields

The Declaration's vision of public compute is collective: university, national, and international clusters, administratively and financially independent of industry — a **city wall**.

SemiBridge walks the complementary road: **a sovereign terminal for every person**. Your own machine, your own keys, your own model choices, your own memory — a **shield**.

Neither works alone:

- A wall without shields: you queue three years for the public cluster, and your data still lives on someone else's machines.
- Shields without a wall: personal terminals stay free, but frontier models remain monopolized by a handful of companies; the wall is the collective bargaining chip.

SemiBridge does not replace the public cluster. SemiBridge is the **personal-side starting point** of public infrastructure: installable today, usable today, sovereignty recovered today. And the Slot System lets any open-source GitHub project move in and run — the first footpath between the wall and the shields.

---

## 4. The Qubit Oasis

In the SemiDAO charter's vision, the bridge is an "oasis of AI sovereignty and freedom." This section makes its physical foundation explicit — two editions: one for the poetry, one for the engineering.

### 4.1 The metaphor: touching leaves a trace

Quantum mechanics has an iron law: the **no-cloning theorem** — an unknown quantum state cannot be perfectly copied.

Classical data enjoys no such protection. Classical bits can be copied, harvested, and fed to models without limit, and you will never know — for the past decade, the data of all humanity became the moat of a few companies this way. **In the classical world, "ownership" is a license the powerful issue you**: the platform changes one clause, and your data is no longer yours.

Holding a qubit is a physical fact, not a legal fiction. An unknown quantum state cannot be copied; any read necessarily disturbs it; the disturbance is necessarily detectable. **Touching leaves a trace** — not because a law forbids it, but because the universe testifies.

This is precisely the isomorphic principle of the DataPathGate: any request outside the whitelist is blocked before it is ever sent, and the attempt is logged. The transparency demanded by the Leiden Declaration, SemiBridge's 90-day ledger, and the no-cloning theorem of quantum physics — three domains stating the same sentence:

**Access that cannot be seen should not exist.**

"The Qubit Oasis" means: a digital home where ownership is guaranteed by physics and by code — not by license.

### 4.2 The engineering: a PQC-ready foundation of trust

Beyond the metaphor, "quantum" has a precise engineering anchor: **Post-Quantum Cryptography (PQC)**.

Threat model: once quantum computers scale, Shor's algorithm breaks ECDSA and RSA in polynomial time — the foundation of most digital signatures today. SHA-256 suffers only Grover's quadratic speedup; its security margin remains sufficient after halving.

The oasis's chain of trust is designed accordingly:

| Asset | Current | Quantum threat | Migration path |
|---|---|---|---|
| Ledger hash chain | SHA-256 | Low (Grover halves margin; still ample) | Keep; upgrade track starts at SHA-384 |
| OpenTimestamps Bitcoin anchoring | hash in OP_RETURN (pure hashing) | Low (timestamp proofs rely on hashing and proof-of-work, not on forgeable signatures rewriting history) | Keep; keep anchoring new milestones |
| Digital signatures (Reggie registration; future charter amendments) | Current standards | **High (Shor)** | Migration track: NIST FIPS 204 (ML-DSA) / FIPS 205 (SLH-DSA); pluggable signature algorithms |

The commitment is not "we do quantum computing." It is that **the oasis's foundation of trust is PQC-ready**: the signature migration path is drawn into the architecture ten years before quantum attacks become real — in step with Bitcoin's own long-term security debates and the NIST standardization process of 2024. Engineering discipline that thinks ahead of the attacker.

### 4.3 Boundary statement (honesty clause)

- Quantum **computing** is not on SemiBridge's current roadmap. "Qubit Oasis" denotes the sovereignty metaphor plus the PQC engineering commitment, each with explicit boundaries.
- The no-cloning theorem protects the communication and holding of quantum states, not the storage of ordinary data. Sovereignty over classical data rests on the DataPathGate, trace scrubbing, and open-source auditability — all shipped today.
- PQC migration is a progressive track, not a completed state. The table above is a design commitment; implementation progress is tracked in the repo's commit history.

---

## 5. Commitments

As SemiBridge's formal response to the Leiden Declaration's call:

1. **The Leiden Declaration (DOI: 10.5281/zenodo.20302944) enters our manifesto's references**, and this alignment document will be anchored via OpenTimestamps together with the charter corpus.
2. **The GitHub project page's core-values narrative is revised around knowledge sovereignty** — covision is the method; sovereignty is the mission.
3. **The PQC migration track enters the roadmap**: pluggable signature layer (ML-DSA / SLH-DSA); hash-chain upgrade track starting at SHA-384.
4. To the mathematics community and the open-source world: every layer of SemiBridge's sovereignty design (DataPathGate, Golden Keys, trace scrubbing, the ledger) is Apache-2.0 and freely portable — **the hard part is not the technology; it is the discipline of cheating at none of the layers.**

---

## 6. Sources

**Primary**

- Leiden Declaration full text and signatories: <https://leidendeclaration.ai> (DOI: 10.5281/zenodo.20302944; published 2026-06-02; IMU-endorsed)
- OpenAI announcement: *Sharing AI progress in mathematics*, 2026-10-06 — <https://openai.com/index/sharing-ai-progress-in-mathematics>
- OpenAI manuscript repository: <https://github.com/openai/math>

**Secondary (cross-verification)**

- Retraction Watch: *OpenAI withdraws three preprints a day after releasing 722 manuscripts* (2026-10-08) — 3 withdrawn, 14 revised, ~50% of results released unconfirmed (per AGMAI's recommendation), AHM statement
- The Economist (2026-10-07), Scientific American (2026-10-06), Science (2026-10-07), The Verge — cross-confirmation of 722 manuscripts / 372 result families
- mathandai.org — 8,000+ researcher endorsements

**Internal primary documents (verifiable in git log)**

- Data Sovereignty Manifesto v1.0 (2026-09-15) — `docs/DATA_SOVEREIGNTY_MANIFESTO.md`
- SemiDAO Founding Charter v0 (sealed 2026-10-02) — `semidao-founding-charter-v0.md`
- OpenTimestamps anchoring ledger and ring-pattern — `錨定狀態-2026-10-06.md`

---

*This document was written by a human and an AI, together. Every line of the alignment is covision in practice.*
