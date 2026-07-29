"use client";

import { useAccount, useReadContract } from "wagmi";
import { notchTokenAbi } from "@/lib/abis";
import { useTargetChain } from "@/lib/reads";
import { fmtToken } from "@/lib/format";

/**
 * The connected wallet's stakeable balance.
 *
 * This replaced a faucet button. The token no longer has a mint function — supply
 * is fixed at deployment — and on mainnet the collateral is an asset we do not
 * control at all, so there was nothing for the button to call. The balance is the
 * part that was actually useful: it tells you what you can stake.
 */
export function Balance() {
  const { address } = useAccount();
  const { deployment, chainId } = useTargetChain();
  const token = deployment?.NotchToken;

  const { data: balance } = useReadContract({
    address: token,
    abi: notchTokenAbi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    chainId,
    query: { enabled: !!token && !!address, refetchInterval: 8000 },
  });

  const { data: symbol } = useReadContract({
    address: token,
    abi: notchTokenAbi,
    functionName: "symbol",
    chainId,
    query: { enabled: !!token },
  });

  if (!address || !token) return null;

  return (
    <span className="text-sm text-muted">
      Balance:{" "}
      <span className="text-cream font-semibold">
        {fmtToken(balance as bigint | undefined)} {(symbol as string) ?? "NOTCH"}
      </span>
    </span>
  );
}
