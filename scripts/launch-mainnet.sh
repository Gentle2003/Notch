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
MAINNET_RPC="https://rpc.mainnet.chain.robinhood.com"
RPC="${RPC:-$MAINNET_RPC}"

# Anything not pointed at real mainnet is a rehearsal: deploy and verify exactly as
# normal, but never commit, never push, and put every touched file back. Without
# this a fork run would publish addresses that exist only on a local chain, and
# Vercel would happily deploy the live site against them.
REHEARSAL=0
[[ "$RPC" != "$MAINNET_RPC" ]] && REHEARSAL=1
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

if [[ "$REHEARSAL" == "1" ]]; then
  printf '\n\033[33m REHEARSAL — %s\033[0m\n' "$RPC"
  printf '\033[33m Nothing will be committed or pushed; local files are restored at the end.\033[0m\n'
fi

# Snapshot anything the script rewrites, so a rehearsal leaves no trace.
RESTORE=(contracts/deployments/4663.json web/lib/contracts.ts)
if [[ "$REHEARSAL" == "1" ]]; then
  TMPDIR_SNAP=$(mktemp -d)
  for f in "${RESTORE[@]}"; do
    [[ -f "$ROOT/$f" ]] && cp "$ROOT/$f" "$TMPDIR_SNAP/$(echo "$f" | tr / _)"
  done
  restore() {
    for f in "${RESTORE[@]}"; do
      snap="$TMPDIR_SNAP/$(echo "$f" | tr / _)"
      [[ -f "$snap" ]] && cp "$snap" "$ROOT/$f"
    done
    rm -rf "$TMPDIR_SNAP"
  }
  trap restore EXIT
fi

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
# Lowercase via tr, not ${var,,} — that is bash 4 syntax and macOS ships bash 3.2,
# where it aborts the script. This is the check that confirms the market bound to
# the token you asked for, so it silently not running is the worst possible failure.
BOUND_LC=$(printf '%s' "$BOUND" | tr '[:upper:]' '[:lower:]')
TOKEN_LC=$(printf '%s' "$TOKEN" | tr '[:upper:]' '[:lower:]')
[[ "$BOUND_LC" == "$TOKEN_LC" ]] || fail "collateral mismatch: bound to $BOUND, expected $TOKEN"
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
if [[ "$REHEARSAL" == "1" ]]; then
  say "Rehearsal complete — nothing committed, local files restored."
  echo "  NotchMarket  $MARKET  (exists only on $RPC)"
  echo "  Reputation   $REPUTATION"
  echo
  echo "  Re-run without RPC= to deploy for real."
  exit 0
fi

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
