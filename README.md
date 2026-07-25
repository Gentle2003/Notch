# Notch

**Stake on the signal, not the noise.**

Notch is a **research-quality staking market** on [Robinhood Chain](https://robinhood.com/us/en/chain/). It's a "true Reppo" for RWA & meme research: analysts stake capital on their analysis being high-signal, expert reviewers stake to grade it, and the market's capital prices the truth. The sharpest analysts earn non-transferable on-chain **reputation** ("Reps").

Open-source. Built for Robinhood Chain.

---

## How it works

1. **Stake to submit** — a researcher posts an analysis (a link/CID to the full write-up) and stakes `NOTCH` on it being high-signal. Skin in the game means no free spam.
2. **Experts stake to judge** — reviewers stake **YES** (signal) or **NO** (noise). Higher-trust datanets are gated by earned Reps, so only proven analysts can review there.
3. **Market resolves** — when the review window closes, the side with more reviewer stake wins. Losers are slashed; winners split the losing pool pro-rata and earn Reps.

The submitter counts as a YES-side participant: they win alongside YES reviewers, and are slashed alongside them if NO prevails. **Every payout is funded entirely by staked collateral** — the contract never owes money it doesn't hold. Notably, the submitter's own stake does *not* count toward the YES/NO vote, so a researcher can't self-validate by staking big.

## Architecture

```
Notch/
├── contracts/        Foundry (Solidity 0.8.28)
│   ├── NotchToken     ERC-20 testnet collateral + rate-limited faucet
│   ├── Reputation     Non-transferable "Reps" ledger (soulbound)
│   └── NotchMarket    Datanets + artifacts + stake / resolve / claim
└── web/              Next.js 15 · wagmi/viem · RainbowKit · Tailwind
```

- **NotchMarket** is a single registry (struct-keyed), not one contract per artifact — cheaper and easier to index.
- **Reputation** is soulbound: no transfer/approve, so reputation must be earned, not bought.
- Resolution is deterministic and on-chain (heavier reviewer side wins); no external oracle needed for the MVP.

## Robinhood Chain

| Network | chainId | RPC | Explorer |
|---|---|---|---|
| Testnet | 46630 | https://rpc.testnet.chain.robinhood.com | explorer.testnet.chain.robinhood.com |
| Mainnet | 4663 | https://rpc.mainnet.chain.robinhood.com | robinhoodchain.blockscout.com |

Arbitrum Orbit L2, full EVM, ETH gas — so Foundry contracts and the standard wagmi/viem stack work unchanged.

## Develop

```bash
# 1. contracts: test + local deploy
cd contracts && forge test
anvil &                                   # local chain on :8545
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 2. web (reads the local Anvil deploy; NEXT_PUBLIC_DEFAULT_CHAIN=31337)
pnpm install
pnpm --filter @notch/web dev              # http://localhost:3010
```

The Anvil deploy uses deterministic addresses that match `web/lib/contracts.ts`, so local dev works out of the box.

## Deploy to Robinhood testnet

```bash
cd contracts
PRIVATE_KEY=<your-testnet-key> forge script script/Deploy.s.sol \
  --rpc-url https://rpc.testnet.chain.robinhood.com --broadcast --private-key <your-testnet-key>
```

Then copy the printed addresses into `web/lib/contracts.ts` under chainId `46630`, and set `NEXT_PUBLIC_DEFAULT_CHAIN=46630` in `web/.env.local`.

## Status

Tier-2 MVP: full staking economics on real contracts + testnet-ready web app.

- ✅ Contracts + 11 passing Foundry tests (payouts, slashing, Reps, rep-gating, full collateralization)
- ✅ Deploy script seeds starter datanets and writes addresses to `deployments/<chainId>.json`
- ✅ Web app: datanets, artifact detail, submit, stake YES/NO, resolve, claim, leaderboard, faucet
- ⬜ Next: testnet deploy, off-chain content storage (IPFS), dispute/appeal window, indexer for reviewer leaderboard

## License

MIT
