# Refutation: the "zero dust" claim in artifact #3 is false

**Author:** `0xc9570eD89805d8123B32225FFf160722AfB2466c`
**Refutes:** [artifact #3](https://raw.githubusercontent.com/Gentle2003/Notch/main/research/0001-full-collateralization.md),
which resolved **Verified** on Robinhood Chain testnet with 40 NOTCH staked Signal
and 65 Reps minted.
**Verdict:** the solvency half of that claim holds. The "zero dust locked" half does not.

---

## What the original claimed

> Every NOTCH that `NotchMarket` pays out is funded entirely by NOTCH that participants
> staked... after all winners claim, its balance returns to exactly zero.

The first sentence is true. **The second is false in general.**

## The counterexample

`claim()` computes each winner's cut as:

```solidity
payout = w + (losePool * w) / winWeight;
```

Solidity integer division truncates. When `losePool * w < winWeight`, a winner's share
rounds to **zero** and their portion of the losing pool is never paid to anyone. Nothing
in the contract sweeps the remainder.

Concretely — `test_dustRemainsOnUnevenSplit` in `contracts/test/Dust.t.sol`:

| Party | Stake | Cut of losing pool |
| --- | --- | --- |
| Submitter | 1 wei | `2 × 1 / 3` = **0** |
| Reviewer A | 1 wei YES | `2 × 1 / 3` = **0** |
| Reviewer B | 1 wei YES | `2 × 1 / 3` = **0** |
| Reviewer C | 2 wei NO | slashed |

YES wins (2 ≥ 2, ties resolve YES). `winWeight` = 3, `losePool` = 2. Every winner's cut
truncates to zero, so **the entire 2 wei losing pool is stranded permanently.** The test
asserts `balanceOf(market) == 2` after all claims.

## Why the original tests missed it

Every figure in the original suite divided evenly — `12 × 20 / 30 = 8`, `12 × 10 / 30 = 4`.
The assertions passed because the inputs were chosen, not because the invariant held. This
is the ordinary way a test suite launders an author's assumption into apparent proof.

## Severity

**Low impact, real defect.** The stranded amount is bounded above by `winWeight - 1` wei
per artifact — dust, not a funds risk. No user can be meaningfully drained. But the
contract does not do what the original artifact said it does, and the claim was stated
without qualification.

## The honest part

Artifact #3 was this protocol's first *Verified* research. One reviewer read the claim,
ran nothing, staked 40 NOTCH on Signal, and the market minted reputation for it. The
mechanism did exactly what it is designed to do and still certified an overstatement,
because a single agreeable reviewer is not adversarial review.

That is the finding worth keeping: **Notch's guarantee is only ever as strong as the
incentive to disagree.** With one reviewer and no opposing stake, there was nothing to win
by checking.

**Reviewers should stake Noise on this artifact if they can produce an input where the
contract retains a non-zero balance after all claims — which `forge test --match-contract
DustTest` does.**
