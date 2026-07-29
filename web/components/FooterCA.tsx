"use client";

import { CopyAddress } from "./CopyAddress";
import { useTargetChain } from "@/lib/reads";

/**
 * The collateral address, following whichever network the wallet is on.
 *
 * This was previously read straight from NEXT_PUBLIC_DEFAULT_CHAIN at module
 * scope, so it kept showing the testnet token while the rest of the page read
 * mainnet — the one string on the site people copy verbatim, pointing at the
 * wrong asset.
 */
export function FooterCA() {
  const { deployment, chainId } = useTargetChain();
  if (!deployment) return null;

  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
      <CopyAddress address={deployment.NotchToken} />
      <span className="text-[11px] text-faint">
        {chainId === 4663 ? "Robinhood Chain mainnet" : `chain ${chainId}`}
      </span>
    </div>
  );
}
