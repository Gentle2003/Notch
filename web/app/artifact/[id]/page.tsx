"use client";

import { use } from "react";
import Link from "next/link";
import { useArtifact, useDatanets } from "@/lib/reads";
import { ConsensusBar } from "@/components/ConsensusBar";
import { StakePanel } from "@/components/StakePanel";
import { Faucet } from "@/components/Faucet";
import { IntegrityBadge } from "@/components/IntegrityBadge";
import { fmtToken, shortAddr, timeLeft } from "@/lib/format";

export default function ArtifactPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const artifactId = Number(id);
  const { artifact: a, refetch } = useArtifact(artifactId);
  const { datanets } = useDatanets();

  if (!a) {
    return <div className="py-16 text-center text-muted">Loading artifact…</div>;
  }

  const datanet = datanets.find((d) => d.id === a.datanetId);
  const resolved = a.status === 1;

  return (
    <main className="grid lg:grid-cols-[1fr_360px] gap-6 pt-4">
      {/* Main */}
      <div className="space-y-6">
        <div>
          <Link href="/" className="text-sm text-muted hover:text-white">
            ← All datanets
          </Link>
          <div className="flex items-center gap-2 mt-3 mb-2">
            {datanet && (
              <Link href={`/datanet/${datanet.id}`} className="pill bg-surface-2 text-muted hover:text-white">
                {datanet.name}
              </Link>
            )}
            {resolved && (
              <span className={`pill ${a.outcomeYes ? "bg-orange/15 text-orange" : "bg-no/15 text-no"}`}>
                {a.outcomeYes ? "✓ Verified" : "✗ Rejected"}
              </span>
            )}
          </div>
          <h1 className="text-2xl font-bold leading-tight">{a.title}</h1>
          <div className="text-sm text-muted mt-2">
            Submitted by <span className="text-white">{shortAddr(a.submitter)}</span>
            {!resolved && <> · {timeLeft(a.reviewDeadline)}</>}
          </div>
        </div>

        <div className="card p-5">
          <div className="flex items-center justify-between gap-3 mb-3">
            <h2 className="text-sm font-semibold text-muted">Analysis</h2>
            <IntegrityBadge uri={a.contentURI} contentHash={a.contentHash} />
          </div>
          {a.contentURI ? (
            <a
              href={a.contentURI.startsWith("http") ? a.contentURI : undefined}
              target="_blank"
              rel="noreferrer"
              className="text-orange break-all hover:underline"
            >
              {a.contentURI}
            </a>
          ) : (
            <p className="text-muted text-sm">No content link provided.</p>
          )}
          <div className="mt-3 pt-3 border-t border-border">
            <IntegrityBadge uri={a.contentURI} contentHash={a.contentHash} showDetail />
          </div>
        </div>

        <div className="card p-5">
          <h2 className="text-sm font-semibold text-muted mb-4">Market consensus</h2>
          <ConsensusBar yesStake={a.yesStake} noStake={a.noStake} />
          <div className="grid grid-cols-3 gap-4 mt-5 text-center">
            <Stat label="Submitter stake" value={`${fmtToken(a.submitStake)}`} />
            <Stat label="YES pool" value={`${fmtToken(a.yesStake)}`} accent="orange" />
            <Stat label="NO pool" value={`${fmtToken(a.noStake)}`} accent="no" />
          </div>
        </div>
      </div>

      {/* Sidebar */}
      <div className="space-y-4">
        <div className="flex justify-end">
          <Faucet />
        </div>
        <StakePanel a={a} refetch={refetch} />
      </div>
    </main>
  );
}

function Stat({
  label,
  value,
  accent,
}: {
  label: string;
  value: string;
  accent?: "orange" | "no";
}) {
  return (
    <div>
      <div
        className={`text-lg font-bold ${accent === "orange" ? "text-orange" : accent === "no" ? "text-no" : "text-white"}`}
      >
        {value}
      </div>
      <div className="text-[11px] text-muted mt-0.5">{label}</div>
    </div>
  );
}
