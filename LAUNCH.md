# Launch runbook

Deploying Notch against a new token is one command. Everything that takes time is
done beforehand — the point of this document is that launch day contains no
decisions.

```bash
./scripts/launch-mainnet.sh 0xYourTokenAddress
```

Roughly 60–90 seconds: pre-flight, simulate, deploy, verify, push. Vercel picks up
the push and redeploys in another minute or so.

---

## Do these before launch day

Each one is slow, and each one is a reason a launch stalls.

**1. Fund the deployer.** At least 0.0005 ETH on chain 4663. The script refuses to
run below that rather than failing halfway through.

```bash
cast balance --rpc-url https://rpc.mainnet.chain.robinhood.com \
  $(cd contracts && cast wallet address --private-key $(grep PRIVATE_KEY .env | cut -d= -f2))
```

**2. Decide who owns it.** The deploying key becomes owner and controls the pause,
the reputation multiplier cap, and minting authority. It cannot touch staked funds —
there is no withdraw path — but it should not be a throwaway key in a plaintext
`.env` once real money is involved. Either deploy from a key you actually hold, or
`transferOwnership` to a Safe immediately afterwards on both contracts.

**3. Rehearse against a fork.** This is the step worth not skipping.

```bash
anvil --fork-url https://rpc.mainnet.chain.robinhood.com &
RPC=http://127.0.0.1:8545 ./scripts/launch-mainnet.sh 0xYourTokenAddress
```

Any RPC that is not real mainnet puts the script in rehearsal mode: it deploys and
verifies exactly as normal against the fork, then restores every file it touched and
exits without committing or pushing. Real mainnet is never contacted and the
deployer's real balance and nonce are untouched — the fork has its own copy of both.

Verified rather than assumed: a full rehearsal leaves HEAD and the working tree
byte-identical, and the live market's artifact count unchanged.

**4. Check the token is usable as collateral.** The script verifies it is an ERC-20
with non-zero supply, but it cannot detect a transfer fee, and that is the one
property that breaks the market. A fee-on-transfer token makes the contract credit
you more than it received, and the shortfall lands on whoever claims last.

```bash
forge test --match-contract ForkIntegrationTest
```

Point the constants in `test/ForkIntegration.t.sol` at the new token first. If
`transfer(1000)` does not deliver exactly 1000, **do not use it as collateral.**

**5. Re-denominate the parameters.** Every minimum is expressed in whole tokens, not
value. `minChallengeBond` defaults to 10 tokens and datanet minimums to 10–50. At
$5 a token that is a $50 appeal; at $0.0001 it is spam. Adjust in
`script/DeployMainnet.s.sol` before launching, not after.

---

## After the deploy

- Set `NEXT_PUBLIC_DEFAULT_CHAIN=4663` in Vercel so mainnet is the default network.
- Verify the contracts on Blockscout so people can read what they are staking into.
- Transfer ownership to a multisig.

## If something goes wrong

The script aborts before broadcasting on any pre-flight failure, and verifies
datanet count, collateral binding and mint authorisation after. If it fails *after*
broadcasting, the contracts exist but the web app was not updated — the addresses
are in `contracts/deployments/4663.json`, and the collateral binding is immutable,
so a wrong token means redeploying rather than repairing.

Fastest safety valve if something is wrong post-launch:

```bash
cast send --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --private-key $PRIVATE_KEY <market> "pause()"
```

That stops new stakes. It deliberately does not stop `resolve`, `finalize` or
`claim`, so nobody's money is trapped by the pause itself.
