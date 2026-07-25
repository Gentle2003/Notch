"use client";

import { use } from "react";
import Link from "next/link";
import { useDatanets, useArtifacts } from "@/lib/reads";
import { ArtifactCard } from "@/components/ArtifactCard";
import { fmtToken } from "@/lib/format";

export default function DatanetPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const datanetId = Number(id);
  const { datanets } = useDatanets();
  const { artifacts } = useArtifacts();

  const d = datanets.find((x) => x.id === datanetId);
  const items = artifacts.filter((a) => a.datanetId === datanetId).reverse();

  return (
    <main className="pt-4 space-y-6">
      <div>
        <Link href="/" className="text-sm text-muted hover:text-white">
          ← All datanets
        </Link>
        <div className="flex items-center justify-between mt-3">
          <div>
            <h1 className="text-2xl font-bold flex items-center gap-2">
              {d?.name ?? `Datanet #${datanetId}`}
              {d && d.minReviewerRep > 0n && (
                <span className="pill bg-lime/10 text-lime">🔒 {d.minReviewerRep.toString()} Reps to review</span>
              )}
            </h1>
            {d && <p className="text-muted mt-1.5 max-w-2xl">{d.description}</p>}
          </div>
          <Link href={`/submit?datanet=${datanetId}`} className="btn-primary whitespace-nowrap">
            Submit here
          </Link>
        </div>
        {d && (
          <div className="text-sm text-muted mt-3">
            Minimum submit stake: <span className="text-white">{fmtToken(d.minSubmitStake)} NOTCH</span>
          </div>
        )}
      </div>

      {items.length === 0 ? (
        <div className="card p-8 text-center text-muted">
          No research submitted yet. Be the first to stake a thesis here.
        </div>
      ) : (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {items.map((a) => (
            <ArtifactCard key={a.id} a={a} />
          ))}
        </div>
      )}
    </main>
  );
}
