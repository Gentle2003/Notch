"use client";

import { useState } from "react";
import { parseEther } from "viem";
import { useAccount } from "wagmi";
import type { Artifact } from "@/lib/reads";
import { notchMarketAbi } from "@/lib/abis";
import { useApproveAndWrite } from "@/lib/useApproveAndWrite";
import { fmtToken, timeLeft } from "@/lib/format";
import { useReadContract } from "wagmi";

export function StakePanel({ a, refetch }: { a: Artifact; refetch: () => void }) {
  const { address } = useAccount();
  const w = useApproveAndWrite();
  const [amount, setAmount] = useState("50");
  const [pendingSide, setPendingSide] = useState<null | "yes" | "no">(null);

  const now = Math.floor(Date.now() / 1000);
  const closed = now >= Number(a.reviewDeadline);
  const settled = a.status === 2; // Final
  const provisional = a.status === 1; // Challengeable
  const isSubmitter = address?.toLowerCase() === a.submitter.toLowerCase();

  const { data: bond } = useReadContract({
    address: w.market,
    abi: notchMarketAbi,
    functionName: "challengeBond",
    args: [BigInt(a.id)],
    chainId: w.chainId,
    query: { enabled: !!w.market && provisional },
  });

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

  const runSimple = async (fn: "resolve" | "claim" | "finalize" | "challenge") => {
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

  // Final → claim
  if (settled) {
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

  // Provisional outcome: dispute it, or finalise once the window has passed.
  if (provisional) {
    const challengeOpen = now < Number(a.challengeDeadline);
    const needsApprovalForBond = w.needsApproval(bond ? String(Number(bond) / 1e18) : "0");
    return (
      <div className="card p-5 space-y-4">
        <div className={`pill ${a.outcomeYes ? "bg-orange/15 text-orange" : "bg-no/15 text-no"} text-sm`}>
          Provisional: {a.outcomeYes ? "signal" : "noise"}
        </div>
        {challengeOpen ? (
          <>
            <p className="text-sm text-muted">
              Not settled yet. Anyone who disagrees can stake against this and reopen
              review — the bond doubles each round, so defending a wrong call gets
              expensive while challenging once does not.
            </p>
            <p className="text-[11px] text-muted">
              Bond to challenge:{" "}
              <span className="text-cream">{bond ? fmtToken(bond as bigint) : "…"} NOTCH</span>{" "}
              · round {a.round + 1} of 3 · {timeLeft(a.challengeDeadline)}
            </p>
            {needsApprovalForBond ? (
              <button className="btn-primary w-full" disabled={w.busy || w.mining} onClick={w.approve}>
                {w.busy || w.mining ? "Approving…" : "Approve NOTCH"}
              </button>
            ) : (
              <button
                className="btn-no w-full"
                disabled={w.busy || w.mining || isSubmitter}
                onClick={() => runSimple("challenge")}
              >
                {w.busy || w.mining ? "Challenging…" : "Challenge this outcome"}
              </button>
            )}
            {isSubmitter && (
              <p className="text-[11px] text-muted">
                You submitted this, so you can&apos;t challenge it — same rule that stops
                authors backing their own work.
              </p>
            )}
          </>
        ) : (
          <>
            <p className="text-sm text-muted">
              Challenge window closed. Finalise to unlock claims.
            </p>
            <button className="btn-primary w-full" disabled={w.busy || w.mining} onClick={() => runSimple("finalize")}>
              {w.busy || w.mining ? "Finalising…" : "Finalise outcome"}
            </button>
          </>
        )}
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
