"use client";

import { useMemo } from "react";
import { useReadContracts } from "wagmi";
import type { Address } from "viem";
import { useArtifacts, useTargetChain } from "@/lib/reads";
import { reputationAbi } from "@/lib/abis";
import { shortAddr } from "@/lib/format";

export default function LeaderboardPage() {
  const { artifacts } = useArtifacts();
  const { deployment, chainId } = useTargetChain();
  const rep = deployment?.Reputation as Address | undefined;

  // Aggregate submitter activity.
  const rows = useMemo(() => {
    const map = new Map<string, { submissions: number; verified: number }>();
    for (const a of artifacts) {
      const key = a.submitter.toLowerCase();
      const r = map.get(key) ?? { submissions: 0, verified: 0 };
      r.submissions += 1;
      if (a.status === 1 && a.outcomeYes) r.verified += 1;
      map.set(key, r);
    }
    return Array.from(map.entries()).map(([addr, v]) => ({ addr: addr as Address, ...v }));
  }, [artifacts]);

  const { data: reps } = useReadContracts({
    contracts: rows.map((r) => ({
      address: rep as Address,
      abi: reputationAbi,
      functionName: "repOf" as const,
      args: [r.addr] as const,
      chainId,
    })),
    query: { enabled: !!rep && rows.length > 0, refetchInterval: 10000 },
  });

  const ranked = useMemo(() => {
    return rows
      .map((r, i) => ({ ...r, reps: Number((reps?.[i]?.result as bigint | undefined) ?? 0n) }))
      .sort((a, b) => b.reps - a.reps || b.verified - a.verified);
  }, [rows, reps]);

  return (
    <main className="pt-4 space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Reputation leaderboard</h1>
        <p className="text-muted mt-1.5 max-w-2xl text-sm">
          Reps are non-transferable — earned only by staking correctly on research quality.
          They gate access to higher-trust datanets. (Shows analysts who&apos;ve submitted;
          reviewer-only Reps accrue on-chain too.)
        </p>
      </div>

      {ranked.length === 0 ? (
        <div className="card p-8 text-center text-muted">No activity yet.</div>
      ) : (
        <div className="card overflow-hidden">
          <table className="w-full text-sm">
            <thead className="text-muted text-xs border-b border-border">
              <tr>
                <th className="text-left font-medium px-5 py-3">#</th>
                <th className="text-left font-medium px-5 py-3">Analyst</th>
                <th className="text-right font-medium px-5 py-3">Reps</th>
                <th className="text-right font-medium px-5 py-3">Verified</th>
                <th className="text-right font-medium px-5 py-3">Submissions</th>
              </tr>
            </thead>
            <tbody>
              {ranked.map((r, i) => (
                <tr key={r.addr} className="border-b border-border/50 last:border-0">
                  <td className="px-5 py-3.5 text-muted">{i + 1}</td>
                  <td className="px-5 py-3.5 font-mono">{shortAddr(r.addr)}</td>
                  <td className="px-5 py-3.5 text-right font-bold text-orange">{r.reps}</td>
                  <td className="px-5 py-3.5 text-right">{r.verified}</td>
                  <td className="px-5 py-3.5 text-right text-muted">{r.submissions}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </main>
  );
}
