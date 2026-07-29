#!/usr/bin/env bash
# Launch Notch on Robinhood Chain mainnet against a given collateral token.
#
#   ./scripts/launch-mainnet.sh 0xYourTokenAddress
#
# Runs pre-flight checks, deploys, points the web app at the new addresses and
# pushes (which triggers the Vercel deploy). Aborts on anything unexpected —
# the market's collateral binding is immutable, so a bad address is permanent.
#
# Everything slow is done in advance; see LAUNCH.md.

set -euo pipefail

TOKEN="${1:-}"
RPC="${RPC:-https://rpc.mainnet.chain.robinhood.com}"
CHAIN_ID=4663
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/contracts"

if [[ -z "$TOKEN" ]]; then
  echo "usage: $0 <collateral-token-address>" >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a; source .env; set +a
DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
fail() { printf '\033[31mABORT: %s\033[0m\n' "$1" >&2; exit 1; }

say "1/5  Pre-flight"

CODE=$(cast code --rpc-url "$RPC" "$TOKEN")
[[ "$CODE" == "0x" || -z "$CODE" ]] && fail "no contract at $TOKEN on chain $CHAIN_ID"

SYMBOL=$(cast call --rpc-url "$RPC" "$TOKEN" 'symbol()(string)' 2>/dev/null) || fail "not an ERC-20 (no symbol)"
DECIMALS=$(cast call --rpc-url "$RPC" "$TOKEN" 'decimals()(uint8)' 2>/dev/null) || fail "not an ERC-20 (no decimals)"
SUPPLY=$(cast call --rpc-url "$RPC" "$TOKEN" 'totalSupply()(uint256)' 2>/dev/null | awk '{print $1}')
[[ "$SUPPLY" == "0" ]] && fail "token reports zero supply"

echo "  token    $SYMBOL ($TOKEN)"
echo "  decimals $DECIMALS"
echo "  supply   $(cast from-wei "$SUPPLY" 2>/dev/null || echo "$SUPPLY")"

BAL=$(cast balance --rpc-url "$RPC" "$DEPLOYER" | awk '{print $1}')
echo "  deployer $DEPLOYER"
echo "  gas      $(cast from-wei "$BAL") ETH"
node -e "process.exit(BigInt('$BAL') >= 500000000000000n ? 0 : 1)" \
  || fail "deployer needs at least 0.0005 ETH on chain $CHAIN_ID"

say "2/5  Simulating against live mainnet state"
COLLATERAL="$TOKEN" forge script script/DeployMainnet.s.sol --rpc-url "$RPC" >/tmp/notch-sim.log 2>&1 \
  || { tail -20 /tmp/notch-sim.log; fail "simulation failed — nothing was broadcast"; }
grep -E "Estimated amount required" /tmp/notch-sim.log | sed 's/^/  /' || true

say "3/5  Deploying"
COLLATERAL="$TOKEN" forge script script/DeployMainnet.s.sol \
  --rpc-url "$RPC" --broadcast --private-key "$PRIVATE_KEY" >/tmp/notch-deploy.log 2>&1 \
  || { tail -30 /tmp/notch-deploy.log; fail "deploy failed"; }

grep -qE "ONCHAIN EXECUTION COMPLETE" /tmp/notch-deploy.log || {
  tail -30 /tmp/notch-deploy.log; fail "deploy did not confirm"; }

MARKET=$(node -e "console.log(require('./deployments/$CHAIN_ID.json').NotchMarket)")
REPUTATION=$(node -e "console.log(require('./deployments/$CHAIN_ID.json').Reputation)")
echo "  NotchMarket $MARKET"
echo "  Reputation  $REPUTATION"

say "4/5  Verifying on-chain"
DN=$(cast call --rpc-url "$RPC" "$MARKET" 'datanetCount()(uint256)' | awk '{print $1}')
BOUND=$(cast call --rpc-url "$RPC" "$MARKET" 'collateral()(address)')
AUTHED=$(cast call --rpc-url "$RPC" "$REPUTATION" 'isMarket(address)(bool)' "$MARKET")
echo "  datanets            $DN"
echo "  collateral bound    $BOUND"
echo "  market authorised   $AUTHED"
[[ "$DN" == "5" ]] || fail "expected 5 datanets, got $DN"
[[ "${BOUND,,}" == "${TOKEN,,}" ]] || fail "collateral mismatch: bound to $BOUND"
[[ "$AUTHED" == "true" ]] || fail "market not authorised to mint Reps"

say "5/5  Pointing the web app at mainnet"
node - "$MARKET" "$REPUTATION" "$TOKEN" <<'NODE'
const fs = require("fs");
const [market, reputation, token] = process.argv.slice(2);
const p = `${process.env.ROOT || ".."}/web/lib/contracts.ts`;
let s = fs.readFileSync(p, "utf8");
if (s.includes("  4663: {")) {
  s = s.replace(/  4663: \{[^}]*\},/s,
    `  4663: {\n    NotchToken: "${token}",\n    Reputation: "${reputation}",\n    NotchMarket: "${market}",\n  },`);
} else {
  s = s.replace("export const deployments: Record<number, Deployment> = {",
    `export const deployments: Record<number, Deployment> = {\n  // Robinhood Chain mainnet\n  4663: {\n    NotchToken: "${token}",\n    Reputation: "${reputation}",\n    NotchMarket: "${market}",\n  },`);
}
fs.writeFileSync(p, s);
console.log("  web/lib/contracts.ts updated");
NODE

cd "$ROOT"
git add -A
git -c user.name="Notch" -c user.email="gentlespreemain@gmail.com" \
  commit -q -m "chore: launch on Robinhood mainnet against $SYMBOL

NotchMarket $MARKET
Reputation  $REPUTATION
collateral  $TOKEN"
git push -q origin main

say "Done."
echo "  NotchMarket  $MARKET"
echo "  Reputation   $REPUTATION"
echo "  collateral   $SYMBOL $TOKEN"
echo "  Vercel will redeploy from the push (~60s)."
echo
echo "  Set NEXT_PUBLIC_DEFAULT_CHAIN=4663 in Vercel to make mainnet the default."
