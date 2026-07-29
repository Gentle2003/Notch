"use client";

import { Suspense, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { parseEther } from "viem";
import { useAccount } from "wagmi";
import { useDatanets, useTargetChain } from "@/lib/reads";
import { useApproveAndWrite } from "@/lib/useApproveAndWrite";
import { notchMarketAbi } from "@/lib/abis";
import { Faucet } from "@/components/Faucet";
import { fmtToken } from "@/lib/format";
import { snapshot as snapshotSource, ZERO_HASH } from "@/lib/verify";

function SubmitForm() {
  const { address } = useAccount();
  const router = useRouter();
  const search = useSearchParams();
  const { datanets } = useDatanets();
  const { chainId, deployment } = useTargetChain();
  const w = useApproveAndWrite();

  const [datanetId, setDatanetId] = useState<number>(Number(search.get("datanet") ?? 0));
  const [title, setTitle] = useState("");
  const [uri, setUri] = useState("");
  const [stake, setStake] = useState("25");
  const [contentHash, setContentHash] = useState<string>(ZERO_HASH);
  const [hashState, setHashState] = useState<
    "idle" | "hashing" | "ok" | "unreachable" | "http-error" | "unstable"
  >("idle");
  const [hashDetail, setHashDetail] = useState<string>("");
  const [showHashHelp, setShowHashHelp] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const selected = datanets.find((d) => d.id === datanetId);
  const minStake = selected ? Number(fmtToken(selected.minSubmitStake).replace(/,/g, "")) : 0;
  const belowMin = Number(stake) < minStake;
  const needsApproval = w.needsApproval(stake);

  // Snapshot the source so reviewers can later detect edits. If the fetch is
  // blocked (CORS is common on X/Twitter), we submit without a commitment
  // rather than failing — but the UI says so plainly.
  const snapshot = async () => {
    if (!uri) {
      setContentHash(ZERO_HASH);
      setHashState("idle");
      return;
    }
    setHashState("hashing");
    const res = await snapshotSource(uri);
    if (res.ok) {
      setContentHash(res.hash);
      setHashState("ok");
    } else {
      setContentHash(ZERO_HASH);
      setHashState(res.reason === "not-http" ? "idle" : res.reason);
      setHashDetail(res.detail ?? "");
    }
  };

  const submit = async () => {
    if (!w.market) return;
    w.setError(null);
    setSubmitting(true);
    try {
      const h = await w.writeContractAsync({
        address: w.market,
        abi: notchMarketAbi,
        functionName: "submitArtifact",
        args: [BigInt(datanetId), title, uri, contentHash as `0x${string}`, parseEther(stake)],
        chainId: w.chainId,
      });
      w.setHash(h);
      setTimeout(() => router.push("/"), 3000);
    } catch (e: any) {
      w.setError(e?.shortMessage ?? e?.message ?? "Submission failed");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <main className="max-w-xl mx-auto pt-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Submit research</h1>
        <Faucet />
      </div>
      <p className="text-muted text-sm -mt-2">
        Post an analysis and stake NOTCH on it being high-signal. Reviewers will grade it —
        win and you split their losing stake plus earn Reps; lose and you&apos;re slashed.
      </p>

      <div className="card p-6 space-y-5">
        {!deployment && (
          <div className="rounded-[3px] border border-no/40 bg-no/10 p-3 text-[12px] leading-relaxed">
            <span className="text-cream">Notch isn&apos;t deployed on this network</span>{" "}
            <span className="text-muted">
              (chain {chainId}). Switch your wallet to Robinhood Chain — mainnet (4663) or
              testnet (46630) — to see datanets.
            </span>
          </div>
        )}

        <div>
          <label className="label">Datanet</label>
          <select
            className="input"
            value={datanetId}
            onChange={(e) => setDatanetId(Number(e.target.value))}
          >
            {datanets.length === 0 && (
              <option value="" disabled>
                {deployment ? "Loading datanets…" : "Unsupported network"}
              </option>
            )}
            {datanets.map((d) => (
              <option key={d.id} value={d.id}>
                {d.name} · min {fmtToken(d.minSubmitStake)} NOTCH
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="label">Title / thesis</label>
          <input
            className="input"
            placeholder="e.g. Tokenized T-bill RWA X is over-collateralized — 8% real yield"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
        </div>

        <div>
          <label className="label">Link to full analysis (https:// or ipfs://)</label>
          <input
            className="input"
            placeholder="https://…"
            value={uri}
            onChange={(e) => setUri(e.target.value)}
            onBlur={snapshot}
          />
          {hashState === "hashing" && (
            <p className="text-[11px] text-muted mt-1.5">Checking the source…</p>
          )}
          {hashState === "ok" && (
            <p className="text-[11px] text-orange mt-1.5">
              ✓ Content hashed — reviewers will be warned if it changes
            </p>
          )}
          {hashState === "http-error" && (
            <p className="text-[11px] text-no mt-1.5">
              Source returned {hashDetail} — check the link is public and correct
            </p>
          )}
          {(hashState === "unstable" || hashState === "unreachable") && (
            <p className="text-[11px] text-faint mt-1.5">
              Not hashable{hashState === "unstable" ? " (source changes every request)" : ""} —
              submitting without tamper-detection.{" "}
              <button
                type="button"
                onClick={() => setShowHashHelp((v) => !v)}
                className="underline hover:text-muted"
              >
                why?
              </button>
            </p>
          )}
          {showHashHelp && (hashState === "unstable" || hashState === "unreachable") && (
            <p className="text-[11px] text-muted mt-1.5 leading-relaxed max-w-prose">
              A hash lets reviewers detect edits made after they staked. It only works on
              sources that return identical bytes each time. X and most social sites embed
              per-request tokens, so a hash would report &quot;changed&quot; forever even if
              you never touched the post. Link an archive snapshot or IPFS if you want the
              guarantee; otherwise this is fine, it just isn&apos;t verifiable.
            </p>
          )}
        </div>

        <div>
          <label className="label">Your submit stake (NOTCH)</label>
          <input
            className="input"
            type="number"
            value={stake}
            onChange={(e) => setStake(e.target.value)}
          />
          {belowMin && (
            <p className="text-xs text-no mt-1.5">Below datanet minimum of {minStake} NOTCH.</p>
          )}
        </div>

        {!address ? (
          <p className="text-sm text-muted">Connect your wallet to submit.</p>
        ) : needsApproval ? (
          <button className="btn-primary w-full" disabled={w.busy || w.mining} onClick={w.approve}>
            {w.busy || w.mining ? "Approving…" : "Approve NOTCH"}
          </button>
        ) : (
          <button
            className="btn-primary w-full"
            disabled={submitting || w.mining || belowMin || !title || !deployment || datanets.length === 0}
            onClick={submit}
          >
            {submitting || w.mining ? "Submitting…" : "Stake & submit"}
          </button>
        )}
        {w.error && <p className="text-xs text-no">{w.error}</p>}
      </div>
    </main>
  );
}

export default function SubmitPage() {
  return (
    <Suspense fallback={<div className="py-16 text-center text-muted">Loading…</div>}>
      <SubmitForm />
    </Suspense>
  );
}
