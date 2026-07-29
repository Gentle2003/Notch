# Resolution v2 — reputation weighting and appeals

**Status:** proposal, not implemented
**Replaces:** `NotchMarket.resolve()` line 219, `a.outcomeYes = a.yesStake >= a.noStake`

---

## 1. The problem

Today the outcome is decided by raw capital:

```solidity
a.outcomeYes = a.yesStake >= a.noStake;
```

A worked attack on the current contract:

| Step | Actor | Amount |
| --- | --- | --- |
| Submit a knowingly false thesis | attacker | 25 |
| Correctly stake Noise | honest reviewers | 1,000 |
| Stake Signal | attacker | 1,001 |
| **Signal wins.** Attacker weight 1,026, losing pool 1,000 | | |
| Withdraws 2,026 having staked 1,026 | attacker | **+1,000** |

The protocol pays the attacker for being wrong, funded by the people who were right. Cost of the attack: gas.

Worthless testnet tokens are the only thing preventing this today.

---

## 2. Design principles

1. **Influence must be expensive to acquire and cheap to lose.** Capital is neither.
2. **Reputation is the one thing on this network that cannot be bought** — `Reputation` has no transfer function, by design.
3. **Solvency is non-negotiable.** Whatever changes, the escrow must still pay out exactly what it took in. The dust-sweep proof must survive.
4. **Newcomers must be able to participate**, or the network never bootstraps.

---

## 3. Reputation-weighted outcomes

### 3.1 The split that makes this safe

**Reputation weights the vote. Capital determines the payout.**

- `effectiveWeight` — used *only* to decide `outcomeYes`
- `payout` — computed from raw stake, exactly as today

This matters for two reasons. It keeps the solvency math untouched (payouts still sum to the pool, so `test_noDustOnUnevenSplit` still holds). And it means reputation buys **influence, not yield** — a high-rep reviewer decides more, but does not extract more per token. Without that split, reputation becomes a rent-seeking position and the incentive to farm it detaches from being correct.

### 3.2 The multiplier

```
repMultiplierBps(reps) = min(MAX_BPS, BASE_BPS + K * sqrt(reps))
```

With `BASE_BPS = 10_000` (1.00×), `K = 600`, `MAX_BPS = 40_000` (4.00×):

| Reps | Multiplier |
| --- | --- |
| 0 | 1.00× |
| 100 | 1.60× |
| 400 | 2.20× |
| 900 | 2.80× |
| 1,600 | 3.40× |
| 2,500+ | 4.00× (capped) |

Square root, not linear: influence keeps growing with a track record but with diminishing returns, so no single reviewer becomes a dictator. `BASE_BPS = 10_000` means a zero-rep reviewer still counts at face value — they are diluted, never silenced. The cap bounds worst-case concentration to a number you can state publicly.

`sqrt` via OpenZeppelin `Math.sqrt`. All integer math, no floats.

### 3.3 Effective weight

```
effectiveYes = Σ over YES reviewers of  stake_i * repMultiplierBps(reps_i) / 10_000
effectiveNo  = Σ over NO  reviewers of  stake_i * repMultiplierBps(reps_i) / 10_000

outcomeYes = effectiveYes >= effectiveNo
```

The submitter's stake is **excluded** from both, exactly as `consensusBps` already excludes it today. An author does not get a weighted vote on their own work.

**Implementation note.** These sums cannot be computed in `resolve()` by iterating reviewers — unbounded loop, guaranteed gas DoS. They must be accumulated incrementally in `review()`, where the reviewer's reps are read once at stake time. This also fixes the timing question: **reputation is snapshotted when you stake**, so you cannot earn Reps elsewhere mid-window to retroactively strengthen a position.

### 3.4 What this changes for the attacker

Same attack, against a reviewer pool averaging 400 reps (2.20×):

| Side | Raw stake | Multiplier | Effective |
| --- | --- | --- | --- |
| Honest (Noise) | 1,000 | 2.20× | **2,200** |
| Attacker (Signal), 0 reps | 1,001 | 1.00× | 1,001 |

The attack fails. To win, the attacker must stake **>2,200** to capture a 1,000 pool.

**Be precise about what that does and does not achieve.** The attacker's *profit* if they win is still the losing pool — their own stake comes back. What changes is capital efficiency: they must commit 2.2× (rising to 4× at cap) the capital they are trying to steal, and they lose all of it if they are outvoted. It raises the bar and makes the attack capital-hungry. **It does not make it impossible.** Section 5 is what makes it expensive to sustain.

---

## 4. Reputation slashing

Reps are currently **award-only** — `Reputation.award()` exists, nothing removes them. That is a hole: an attacker who builds a track record can spend it once with no consequence.

Add:

```solidity
function slash(address account, uint256 amount) external onlyMarket;
```

Applied on the losing side at claim time, proportional to stake:

```
repSlashed = repOf(loser) * min(BPS_MAX, loserStake * SLASH_RATE / totalLosingStake) / BPS_MAX
```

The effect: a reviewer who spends a large reputation backing a wrong outcome loses a chunk of what took months to earn. Reputation attacks become **single-use**, and the cost is the entire future value of the position.

Keep `SLASH_RATE` well below 100%. Honest reviewers are wrong sometimes; the goal is to make being wrong *sting*, not to wipe out anyone who takes one bad position. Start around 20–30% and tune with real data.

---

## 5. Appeals

Reputation weighting alone still loses to enough capital in a single shot. Appeals remove the single shot.

### 5.1 Mechanics

1. `resolve()` computes a provisional outcome and opens a **challenge window** (48h). No claims yet.
2. Anyone may challenge by posting a bond:

   ```
   bond_n = max(MIN_BOND, 2^n * margin)     where margin = |effectiveYes - effectiveNo|
   ```

3. A challenge reopens review for another round. The bond joins the side the challenger backs.
4. Each further challenge doubles: `2× margin`, then `4×`, then `8×`.
5. After `MAX_ROUNDS` (3), the outcome is final.
6. A successful challenger recovers their bond and shares the newly-losing pool. A failed challenger forfeits the bond to the winners.

### 5.2 Why this bites

Holding a wrong outcome means winning **every** round. Costs compound:

| Round | Attacker must post | Cumulative |
| --- | --- | --- |
| 0 | 4× honest capital (rep-weighted) | 4× |
| 1 | 2× margin | ~6× |
| 2 | 4× margin | ~10× |
| 3 | 8× margin | ~18× |

Honest challengers pay once. The attacker pays every time, with capital locked for days.

### 5.3 Honest limitation

**A rich enough attacker still wins the final round.** Every finite-round appeal system has this property, Kleros and Augur included — they escalate to token forking, which is a far larger build.

The practical mitigation is to keep the prize below the cost: cap per-artifact stake, or scale the cap with the reviewer pool's total reputation, so extractable value can never grow large enough to justify ~18× capital lockup. **This should be stated in the docs rather than glossed** — a protocol claiming attack-proof resolution that isn't invites exactly the person who checks.

---

## 6. Bootstrap

At genesis every reviewer has 0 reps, every multiplier is 1.00×, and resolution degenerates to pure capital — the current design. Reputation weighting only defends a network that already has reputation.

Two options.

**A. Phased cap (recommended).** `MAX_BPS` starts at 15,000 (1.5×) and widens on a published schedule as real reputation accumulates. Predictable, auditable, no cleverness. Requires governance action, so put it behind the same timelock as other admin powers.

**B. Self-scaling cap.** `MAX_BPS = 10_000 + min(30_000, totalRep / N)` — widens automatically as the network matures. Elegant, no discretion, but gameable if Reps turn out to be cheap to farm. Not recommended until the earn rate has been observed under real conditions.

Either way, be explicit publicly: **early markets are capital-weighted and should carry small stakes.** Seeding a founding reviewer set with initial Reps is defensible if disclosed, and corrosive if discovered later.

---

## 7. What this does not fix

- A determined whale can still win the final appeal round (§5.3).
- Reputation earned in one datanet counts everywhere. A top RWA analyst carries full weight into medical theses. Per-datanet reputation is the correct answer and a larger change.
- Nothing here makes the *content* verifiable. `contentHash` detects edits; it does not establish that a claim is true.
- Collusion between high-rep reviewers is unaddressed. Commit-reveal voting would help and is orthogonal.

---

## 8. Implementation order

1. `Reputation.slash()` + tests — no behaviour change, purely additive
2. `repMultiplierBps` as a pure function + fuzz the curve for overflow and monotonicity
3. Accumulate `effectiveYes` / `effectiveNo` in `review()`, snapshotting reps at stake time
4. Switch `resolve()` to effective weights; **payout math untouched**
5. Invariant test: escrow still drains to zero across randomised rep distributions
6. Challenge window + bond escalation
7. Wire reputation slashing into `claim()` on the losing side
8. Frontend: show effective vs raw weight, so people can see *why* a side is winning

Steps 1–5 are the substance and are independently shippable. Steps 6–7 can follow.
