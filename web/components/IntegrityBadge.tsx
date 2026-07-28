"use client";

import { useIntegrity, type Integrity } from "@/lib/verify";

const COPY: Record<Integrity, { label: string; detail: string; cls: string }> = {
  checking: {
    label: "Checking content…",
    detail: "Re-fetching the analysis to compare it against the on-chain hash.",
    cls: "bg-surface-2 text-muted",
  },
  verified: {
    label: "✓ Content unchanged",
    detail: "The analysis hashes to the value committed on-chain at submission.",
    cls: "bg-orange/10 text-orange",
  },
  changed: {
    label: "⚠ Content changed since submission",
    detail:
      "This no longer matches the hash committed on-chain. It may be an honest revision or a substituted argument — either way, reviewers staked on a different version.",
    cls: "bg-no/20 text-cream",
  },
  uncommitted: {
    label: "No content hash",
    detail:
      "The submitter didn't commit a hash, so edits to the source can't be detected. Weigh accordingly.",
    cls: "bg-surface-2 text-muted",
  },
  unreachable: {
    label: "Couldn't verify content",
    detail:
      "The source couldn't be fetched from the browser — often CORS (X/Twitter blocks this), or the page is gone. This is not evidence of tampering.",
    cls: "bg-surface-2 text-muted",
  },
};

/**
 * Surfaces whether an artifact's linked analysis still matches what reviewers
 * staked on. "changed" is the loud state; everything else stays quiet so the
 * warning keeps its meaning.
 */
export function IntegrityBadge({
  uri,
  contentHash,
  variant = "pill",
}: {
  uri?: string;
  contentHash?: string;
  /** "pill" for the scannable chip; "detail" for the explanatory line beneath it. */
  variant?: "pill" | "detail";
}) {
  const state = useIntegrity(uri, contentHash);
  const c = COPY[state];

  if (variant === "detail") {
    return <p className="text-[11px] text-muted leading-relaxed max-w-prose">{c.detail}</p>;
  }
  return <span className={`pill ${c.cls}`}>{c.label}</span>;
}
