"use client";

import { useState } from "react";

/**
 * Share control for a thesis. The point of sharing here isn't vanity — a thesis
 * with no opposing stake resolves on whoever showed up, so pulling in outside
 * readers is what makes the market mean anything.
 */
export function ShareThesis({ id, title }: { id: number; title: string }) {
  const [copied, setCopied] = useState(false);

  const url =
    typeof window !== "undefined"
      ? `${window.location.origin}/artifact/${id}`
      : `https://www.notchmarket.xyz/artifact/${id}`;

  const intent = `https://twitter.com/intent/tweet?text=${encodeURIComponent(
    `${title}\n\nStake signal or noise on it:`,
  )}&url=${encodeURIComponent(url)}`;

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      // Clipboard is blocked outside secure contexts; the X path still works.
      setCopied(false);
    }
  };

  return (
    <div className="flex items-center gap-2">
      <button onClick={copy} className="btn-ghost text-[12px] py-1.5 px-3">
        {copied ? "✓ Link copied" : "Copy link"}
      </button>
      <a
        href={intent}
        target="_blank"
        rel="noreferrer"
        className="btn-outline-orange text-[12px] py-1.5 px-3"
      >
        Share on X
      </a>
    </div>
  );
}
