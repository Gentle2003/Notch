"use client";

import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { notchTokenAbi } from "@/lib/abis";
import { useTargetChain } from "@/lib/reads";
import { fmtToken } from "@/lib/format";

export function Faucet() {
  const { address } = useAccount();
  const { deployment, chainId } = useTargetChain();
  const token = deployment?.NotchToken;

  const { data: bal, refetch } = useReadContract({
    address: token,
    abi: notchTokenAbi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    chainId,
    query: { enabled: !!token && !!address, refetchInterval: 6000 },
  });

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: mining } = useWaitForTransactionReceipt({ hash, query: { enabled: !!hash } });

  if (!address || !token) return null;

  return (
    <div className="flex items-center gap-3">
      <span className="text-sm text-muted">
        Balance: <span className="text-white font-semibold">{fmtToken(bal)} NOTCH</span>
      </span>
      <button
        className="btn-ghost text-xs py-1.5 px-3"
        disabled={isPending || mining}
        onClick={() =>
          writeContract(
            { address: token, abi: notchTokenAbi, functionName: "faucet", chainId },
            { onSuccess: () => setTimeout(() => refetch(), 2500) },
          )
        }
      >
        {isPending || mining ? "Claiming…" : "Get 1,000 NOTCH"}
      </button>
    </div>
  );
}
