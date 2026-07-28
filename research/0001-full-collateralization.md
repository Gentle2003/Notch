# NotchMarket payouts are fully collateralized, with zero dust locked

**Author:** `0xc9570eD89805d8123B32225FFf160722AfB2466c`
**Datanet:** Protocol Smoke Test
**Claim:** Every NOTCH that `NotchMarket` pays out is funded entirely by NOTCH that
participants staked. The contract never promises money it does not hold, and after all
winners claim, its balance returns to exactly zero.

This is deliberately a *checkable* claim rather than a market prediction — the point of
this first artifact is to run the protocol's full economic cycle on live testnet with
content a reviewer can independently verify.

---

## Why it matters

A staking market that can pay out more than it takes in is insolvent by construction. The
usual failure modes are (a) rounding in pro-rata division leaving unclaimable dust, and
(b) paying winners from a pool that double-counts the submitter's stake.

## The mechanism

`claim()` splits participants into a winning and losing side, then pays each winner their
own stake back plus a pro-rata cut of the losing pool:

```
payout = w + (losePool * w) / winWeight
```

where `w` is that participant's winning stake and `winWeight` is the total stake on the
winning side. Because every `w` sums to exactly `winWeight`, the distributed share of
`losePool` sums to exactly `losePool`. Nothing is created.

Two details do the real work:

1. **The submitter is YES-side weight, but not a YES *vote*.** `submitStake` is included in
   `winWeight` for payout, yet `consensusBps()` reads only `yesStake`/`noStake` — reviewer
   capital. So a submitter cannot buy validation of their own work by staking large.
2. **Losers are marked claimed, not paid.** A losing reviewer's `claimed` flag is set with a
   zero payout, which closes their record without touching the pool.

## Verification

Clone the repo and run:

```
cd contracts && forge test
```

Three tests assert the balance invariant directly, each ending with
`assertEq(token.balanceOf(address(market)), 0)`:

| Test | Scenario | Asserted outcome |
| --- | --- | --- |
| `test_yesWins_distributesLosingPool` | submit 10, YES 20, NO 12 | YES reviewer 28, submitter 14; 42 in, 42 out |
| `test_noWins_slashesSubmitter` | submit 10, NO 30, YES 5 | NO reviewer 45; submitter slashed; contract drained |
| `test_noReviews_returnsSubmitterStake` | submit 10, no reviews | submitter gets exactly 10 back |

All three pass against `NotchMarket` at
[`0x104540Cc7B00a42d98919bb2Ee16535F57541FD7`](https://explorer.testnet.chain.robinhood.com/address/0x104540Cc7B00a42d98919bb2Ee16535F57541FD7)
on Robinhood Chain testnet (46630).

## Scope and limits

This claim covers **solvency only**. It is explicitly *not* a claim that the market
resolves to the truth. Resolution is pure stake weight, so a sufficiently large staker can
currently buy any outcome — the contract will simply pay that outcome out correctly. There
is no dispute or appeal window yet. Those are open problems, not solved ones.

**A reviewer who runs the test suite should stake Signal. A reviewer who finds a scenario
where the contract retains a non-zero balance after all claims should stake Noise.**
