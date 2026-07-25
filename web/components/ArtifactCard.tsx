import Link from "next/link";
import type { Artifact } from "@/lib/reads";
import { ConsensusBar } from "./ConsensusBar";
import { fmtToken, shortAddr, timeLeft } from "@/lib/format";

export function ArtifactCard({ a, datanetName }: { a: Artifact; datanetName?: string }) {
  const resolved = a.status === 1;
  return (
    <Link
      href={`/artifact/${a.id}`}
      className="card p-4 block hover:border-lime/40 transition group"
    >
      <div className="flex items-center justify-between mb-2">
        {datanetName ? (
          <span className="pill bg-surface-2 text-muted">{datanetName}</span>
        ) : (
          <span />
        )}
        {resolved ? (
          <span
            className={`pill ${a.outcomeYes ? "bg-lime/15 text-lime" : "bg-no/15 text-no"}`}
          >
            {a.outcomeYes ? "✓ Verified" : "✗ Rejected"}
          </span>
        ) : (
          <span className="pill bg-surface-2 text-muted">{timeLeft(a.reviewDeadline)}</span>
        )}
      </div>

      <h3 className="font-semibold leading-snug mb-3 group-hover:text-lime transition">
        {a.title}
      </h3>

      <ConsensusBar yesStake={a.yesStake} noStake={a.noStake} />

      <div className="flex justify-between text-[11px] text-muted mt-3 pt-3 border-t border-border">
        <span>by {shortAddr(a.submitter)}</span>
        <span>{fmtToken(a.submitStake)} NOTCH at stake</span>
      </div>
    </Link>
  );
}
