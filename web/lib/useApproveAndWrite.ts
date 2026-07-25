"use client";

import { useState } from "react";
import { parseEther, type Address } from "viem";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { notchTokenAbi } from "./abis";
import { useTargetChain } from "./reads";

/**
 * Shared helper for the "approve NOTCH then call a market function that pulls
 * collateral" flow. Reads the current allowance and, if it's short of the
 * requested amount, surfaces `needsApproval` so the UI shows an Approve step.
 */
export function useApproveAndWrite() {
  const { address } = useAccount();
  const { deployment, chainId, market } = useTargetChain();
  const token = deployment?.NotchToken as Address | undefined;

  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: token,
    abi: notchTokenAbi,
    functionName: "allowance",
    args: address && market ? [address, market] : undefined,
    chainId,
    query: { enabled: !!token && !!address && !!market },
  });

  const { writeContractAsync } = useWriteContract();
  const [hash, setHash] = useState<`0x${string}` | undefined>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { isLoading: mining, isSuccess } = useWaitForTransactionReceipt({
    hash,
    query: { enabled: !!hash },
  });

  const needsApproval = (amountEth: string) => {
    if (!amountEth || Number(amountEth) <= 0) return false;
    const wei = parseEther(amountEth);
    return (allowance ?? 0n) < wei;
  };

  const approve = async () => {
    if (!token || !market) return;
    setError(null);
    setBusy(true);
    try {
      const h = await writeContractAsync({
        address: token,
        abi: notchTokenAbi,
        functionName: "approve",
        args: [market, parseEther("1000000000")], // generous allowance for demo UX
        chainId,
      });
      setHash(h);
      // let the receipt land, then refresh allowance
      setTimeout(() => refetchAllowance(), 2500);
    } catch (e: any) {
      setError(e?.shortMessage ?? e?.message ?? "Approval failed");
    } finally {
      setBusy(false);
    }
  };

  return {
    token,
    market,
    chainId,
    allowance,
    needsApproval,
    approve,
    writeContractAsync,
    setHash,
    hash,
    mining,
    isSuccess,
    busy,
    setBusy,
    error,
    setError,
    refetchAllowance,
  };
}
