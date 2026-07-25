"use client";

import { useState } from "react";
import { parseEther } from "viem";
import { useAccount } from "wagmi";
import type { Artifact } from "@/lib/reads";
import { notchMarketAbi } from "@/lib/abis";
import { useApproveAndWrite } from "@/lib/useApproveAndWrite";
import { timeLeft } from "@/lib/format";

export function StakePanel({ a, refetch }: { a: Artifact; refetch: () => void }) {
  const { address } = useAccount();
  const w = useApproveAndWrite();
  const [amount, setAmount] = useState("50");
  const [pendingSide, setPendingSide] = useState<null | "yes" | "no">(null);

  const now = Math.floor(Date.now() / 1000);
  const closed = now >= Number(a.reviewDeadline);
  const resolved = a.status === 1;
  const isSubmitter = address?.toLowerCase() === a.submitter.toLowerCase();

  const stake = async (support: boolean) => {
    if (!w.market) return;
    w.setError(null);
    setPendingSide(support ? "yes" : "no");
    try {
      const h = await w.writeContractAsync({
        address: w.market,
        abi: notchMarketAbi,
        functionName: "review",
        args: [BigInt(a.id), support, parseEther(amount)],
        chainId: w.chainId,
      });
      w.setHash(h);
      setTimeout(() => refetch(), 2500);
    } catch (e: any) {
      w.setError(e?.shortMessage ?? e?.message ?? "Transaction failed");
    } finally {
      setPendingSide(null);
    }
  };

  const runSimple = async (fn: "resolve" | "claim") => {
    if (!w.market) return;
    w.setError(null);
    w.setBusy(true);
    try {
      const h = await w.writeContractAsync({
        address: w.market,
        abi: notchMarketAbi,
        functionName: fn,
        args: [BigInt(a.id)],
        chainId: w.chainId,
      });
      w.setHash(h);
      setTimeout(() => refetch(), 2500);
    } catch (e: any) {
      w.setError(e?.shortMessage ?? e?.message ?? "Transaction failed");
    } finally {
      w.setBusy(false);
    }
  };

  if (!address) {
    return (
      <div className="card p-5 text-sm text-muted">
        Connect your wallet to stake on this research.
      </div>
    );
  }

  // Resolved → claim
  if (resolved) {
    return (
      <div className="card p-5 space-y-4">
        <div
          className={`pill ${a.outcomeYes ? "bg-orange/15 text-orange" : "bg-no/15 text-no"} text-sm`}
        >
          {a.outcomeYes ? "✓ Verified as signal" : "✗ Rejected as noise"}
        </div>
        <p className="text-sm text-muted">
          The market has resolved. Winning stakers can claim their share of the pool plus
          Reps.
        </p>
        <button className="btn-primary w-full" disabled={w.busy || w.mining} onClick={() => runSimple("claim")}>
          {w.busy || w.mining ? "Claiming…" : "Claim winnings"}
        </button>
        {w.error && <p className="text-xs text-no">{w.error}</p>}
      </div>
    );
  }

  // Review window closed → anyone can resolve
  if (closed) {
    return (
      <div className="card p-5 space-y-4">
        <p className="text-sm text-muted">Review window closed. Resolve the market to settle stakes.</p>
        <button className="btn-primary w-full" disabled={w.busy || w.mining} onClick={() => runSimple("resolve")}>
          {w.busy || w.mining ? "Resolving…" : "Resolve market"}
        </button>
        {w.error && <p className="text-xs text-no">{w.error}</p>}
      </div>
    );
  }

  // Submitter can't review their own artifact
  if (isSubmitter) {
    return (
      <div className="card p-5 text-sm text-muted">
        You submitted this artifact — you can&apos;t review your own work. Reviewing closes in{" "}
        <span className="text-white">{timeLeft(a.reviewDeadline)}</span>.
      </div>
    );
  }

  const needsApproval = w.needsApproval(amount);

  return (
    <div className="card p-5 space-y-4">
      <div>
        <label className="label">Your stake (NOTCH)</label>
        <input
          className="input"
          type="number"
          min="1"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
        />
      </div>

      {needsApproval ? (
        <button className="btn-primary w-full" disabled={w.busy || w.mining} onClick={w.approve}>
          {w.busy || w.mining ? "Approving…" : "Approve NOTCH"}
        </button>
      ) : (
        <div className="grid grid-cols-2 gap-3">
          <button
            className="btn-yes"
            disabled={pendingSide !== null}
            onClick={() => stake(true)}
          >
            {pendingSide === "yes" ? "Staking…" : "▲ Signal (YES)"}
          </button>
          <button
            className="btn-no"
            disabled={pendingSide !== null}
            onClick={() => stake(false)}
          >
            {pendingSide === "no" ? "Staking…" : "▼ Noise (NO)"}
          </button>
        </div>
      )}
      <p className="text-[11px] text-muted">
        Reviewing closes in {timeLeft(a.reviewDeadline)}. If your side wins you split the
        losing pool and earn Reps; if it loses, your stake is slashed.
      </p>
      {w.error && <p className="text-xs text-no">{w.error}</p>}
    </div>
  );
}
