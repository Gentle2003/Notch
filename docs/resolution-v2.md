# Resolution v2 — reputation-weighted outcomes

**Status:** implemented; awaiting the next batched redeploy
**Replaces:** `NotchMarket.resolve()` line 219 and the Rep award in `claim()`

---

## 1. Two problems, not one

### 1.1 Outcomes are bought with capital

```solidity
a.outcomeYes = a.yesStake >= a.noStake;
```

Whoever brings more money is right. On mainnet:

| Step | Actor | Amount |
| --- | --- | --- |
| Submit a knowingly false thesis | attacker | 25 |
| Correctly stake Noise | honest reviewers | 1,000 |
| Stake Signal | attacker | 1,001 |
| Signal wins; attacker withdraws 2,026 having staked 1,026 | | **+1,000** |

### 1.2 Reputation is free, and is currently just capital

This is the more damaging one, and it invalidates the obvious fix. Two facts, both proven by `test/RepFarm.t.sol`:

**Reps cost nothing to acquire.** An uncontested artifact resolves YES (`0 >= 0`). With no losing side there is no pool to lose, so every participant is refunded in full *and* paid Reps. Submit to yourself, back it from a second wallet, claim both sides:

```
attacker net tokens: 0
sock net tokens:     0
sock reps:           50,000
```

**Reps are minted in direct proportion to stake:**

```solidity
reps = (myWeight * repPerToken) / 1 ether;   // reps == stake
```

Ten times the capital earns exactly ten times the reputation, at a fixed exchange rate.

Together these mean reputation is **not** independent of money — it is money with a delay. Weighting votes by Reps without fixing this would *amplify* §1.1: farm Reps for free, then apply a 4× multiplier on top of your capital.

**The earn rule must be fixed first. Everything else depends on it.**

---

## 2. Design principles

1. **Influence must be earned by being right when it was hard.** Being right when it was obvious and uncontested says nothing about judgment.
2. **Capital must not convert linearly into reputation**, or reputation is a rebranding of capital.
3. **Solvency is non-negotiable.** Payouts must still sum to the pool; the dust-sweep proof must survive.
4. **Newcomers must be able to participate**, or the network never bootstraps.
5. **Reps are never confiscated.** A track record is a record. Being wrong costs capital, not history.

---

## 3. The vote

### 3.1 The split that keeps this safe

**Reputation weights the vote. Capital determines the payout.**

- `effectiveWeight` decides `outcomeYes` only
- `payout` is computed from raw stake, exactly as today

The escrow math is untouched, so `test_noDustOnUnevenSplit` still holds. And reputation buys **influence, not yield** — a high-rep reviewer decides more but extracts no more per token. Without that split, reputation becomes a rent-seeking position and farming it detaches from being correct.

### 3.2 The expressions

For reviewer *i* with stake *sᵢ* (whole tokens) and effective reputation *rᵢ*:

**Vote multiplier** — how much each token of stake counts:

$$M(r) = \min\left(M_{max},\; 1 + k\sqrt{r}\right)$$

with $M_{max} = 4.0$, $k = 0.06$.

**Effective weight** of one reviewer:

$$w_i = s_i \cdot M(r_i)$$

**Side totals** (the submitter is excluded from both — no weighted vote on your own work):

$$W_{yes} = \sum_{i \in YES} s_i \cdot M(r_i) \qquad W_{no} = \sum_{i \in NO} s_i \cdot M(r_i)$$

**Outcome:**

$$\text{outcomeYes} = W_{yes} \geq W_{no}$$

In integer form, everything in basis points:

```
M_bps(r) = min(40_000, 10_000 + 600 * isqrt(r))
w_i      = stake_i * M_bps(reps_i) / 10_000
```

| Reps | Multiplier |
| --- | --- |
| 0 | 1.00× |
| 100 | 1.60× |
| 400 | 2.20× |
| 900 | 2.80× |
| 1,600 | 3.40× |
| 2,500+ | 4.00× (capped) |

Square root, so influence keeps growing with a track record but with diminishing returns — no reviewer becomes a dictator. `BASE = 1.00×` means a zero-rep reviewer still counts at face value: diluted, never silenced. The cap bounds worst-case concentration to a number you can state publicly.

**Implementation note.** These sums cannot be computed by looping reviewers in `resolve()` — unbounded loop, guaranteed gas DoS. They accumulate in `review()`, reading the reviewer's reps once at stake time. That also closes a timing hole: **reputation is snapshotted when you stake**, so you cannot earn Reps elsewhere mid-window to retroactively strengthen a position.

---

## 4. The earn rule

### 4.1 The expression

Reps are awarded at claim time to the winning side only:

$$\Delta r_i = R \cdot \sqrt{s_i} \cdot C \cdot M$$

where **C is the contest factor**:

$$C = \frac{2 \cdot \min(W_{yes}, W_{no})}{W_{yes} + W_{no}}$$

and $\Delta r_i = 0$ whenever $\min(W_{yes}, W_{no}) = 0$.

In integer form:

```
C_bps  = 20_000 * min(W_yes, W_no) / (W_yes + W_no)     // 0 … 10_000
Δreps  = R * isqrt(stake_i / 1e18) * C_bps / 10_000
```

**M is consensus movement** — how far the market travelled toward you *after* you
committed:

$$M = \max\left(0,\; p_{final} - \bar{p}_{entry}\right)$$

$\bar{p}_{entry}$ is the stake-weighted average share your side already held at the
moment each of your stakes landed (50% for an untouched market, and for the submitter,
who commits before any review exists). $p_{final}$ is the winning side's share at
resolution.

### 4.2 What each term does

**√sᵢ breaks the exchange rate.** 100× the capital earns 10× the reputation, not 100×. Buying influence gets quadratically more expensive.

**C prices difficulty.** It is 1.0 when the market was perfectly split, and falls toward 0 as one side dominates:

| Situation | W_yes : W_no | C | Reps |
| --- | --- | --- | --- |
| Uncontested | 1000 : 0 | **0.00** | **none** |
| Blowout | 1000 : 10 | 0.02 | negligible |
| Contested | 700 : 300 | 0.60 | most |
| Knife-edge | 510 : 490 | 0.98 | full |

**M is what separates conviction from conformity.** Notch has no external referee — being
"right" means agreeing with the eventual majority. Paying for that alone rewards herding,
and because reputation weights future votes, it compounds: agree with the crowd, gain
multiplier, pull harder, agree again. There is nothing outside the loop to correct it.

Movement breaks that without needing any facts. Backing a side at 20% and watching it
close at 70% moved the market. Joining at 90% joined a queue. Both are "on the winning
side"; only one is evidence of judgment. Verified in `test/Movement.t.sol`: two reviewers,
identical stake, same winning side — the early one earns 4 Reps, the late one earns 0.

Without it, the cheapest way to farm reputation was to wait until a market was nearly
settled and pile onto the leader.

**C = 0 when uncontested kills the farm outright.** With no opposition there is no reputation, so the exploit in §1.2 pays nothing. It also stops the subtler version: staking huge amounts on obviously-correct artifacts to grind Reps cheaply. Being right when nobody disagreed is not evidence of judgment, and is no longer paid as if it were.

### 4.3 Calibration

Three sub-1.0 factors multiply, so $R = 1$ rounds ordinary participation to zero — a
20-token stake with 0.75 contest and 0.125 movement earns nothing at all. $R = 5$ puts a
solid call (1,000 staked, 0.8 contest, 0.3 movement) at ~37 Reps, making the 4× cap
roughly 68 sustained good calls. Reaching maximum influence should be hard and slow.
Tune once real distributions are observable.

---

## 5. Decay, not slashing

An earlier draft proposed slashing Reps from the losing side. **Dropped.** It punishes honest reviewers for being occasionally wrong, which is the normal condition of anyone doing real analysis, and it makes participating in close calls — exactly the calls the network needs — the most dangerous thing you can do.

But the concern behind it is real: **if Reps only ever grow, leverage is permanent and reusable.** Farm once, hold 4× forever, attack repeatedly at no lasting cost.

Decay solves that without confiscation:

$$r_{\text{effective}} = r \cdot 2^{-\lfloor \Delta t / T_{1/2} \rfloor}$$

with $T_{1/2} = 180$ days since the account's last correct resolution. As a bit shift:

```
effectiveReps = reps >> (elapsed / HALF_LIFE)
```

Reputation reflects **recent** judgment. Nobody is punished for a bad call; influence simply has to be maintained. Someone who earned 4× two years ago and vanished should not still outvote active reviewers.

Store the raw total as an immutable record — history is preserved, only the weighting decays.

---

## 6. Bootstrap

At genesis everyone has 0 reps, every multiplier is 1.00×, and resolution degenerates to pure capital. Reputation weighting only defends a network that already has reputation.

**Phased cap.** `MAX_BPS` starts at 15,000 (1.5×) and widens on a published schedule as reputation accumulates. Predictable and auditable; put it behind the same timelock as other admin powers.

A self-scaling cap tied to `totalRep` is more elegant but gameable until the earn rate has been observed under real conditions. Not yet.

Say plainly in public that **early markets are capital-weighted and should carry small stakes.** Seeding a founding reviewer set is defensible if disclosed, and corrosive if discovered later.

---

## 7. What this does not fix

- **Enough capital still wins a single round.** Weighting raises the required multiple to 2–4×; it is not a wall. Escalating-bond appeals are the answer and are deferred to a later spec.
- **Reputation is global.** A top RWA analyst carries full weight into medical theses. Per-datanet reputation is correct and is a larger change.
- **Sock-puppet contests.** An attacker can manufacture a contest by funding both sides to raise C. It now costs them real money — the losing wallet is genuinely slashed — but it is not free. Worth modelling before mainnet.
- **Nothing here makes claims verifiable.** `contentHash` detects edits; it does not establish truth.
- **Collusion between high-rep reviewers** is unaddressed. Commit-reveal voting would help and is orthogonal.

---

## 8. Implementation order

1. Keep `test/RepFarm.t.sol` as a standing regression guard — it must go from passing to reverting
2. `repMultiplierBps` and the contest factor as pure functions; fuzz for overflow and monotonicity
3. Replace the earn rule in `claim()` — **this alone closes the live exploit**
4. Accumulate `W_yes` / `W_no` in `review()`, snapshotting reps at stake time
5. Switch `resolve()` to effective weights; **payout math untouched**
6. Invariant test: escrow still drains to zero across randomised rep distributions
7. Decay on read
8. Frontend: show effective vs raw weight so people can see *why* a side is winning

Step 3 is the urgent one and ships independently of everything else.
