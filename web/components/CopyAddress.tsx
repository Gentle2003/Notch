"use client";

import { useState } from "react";

/**
 * The token contract address, click-to-copy. Shown in full rather than
 * truncated — people verifying a token paste the whole string, and a shortened
 * address is exactly what an impersonator would rely on going unchecked.
 */
export function CopyAddress({ address, label = "CA" }: { address: string; label?: string }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    let ok = false;
    try {
      await navigator.clipboard.writeText(address);
      ok = true;
    } catch {
      // The async Clipboard API is unavailable in insecure contexts and denied
      // in some embedded webviews. Fall back to the legacy selection copy so a
      // contract address — the one string people must get byte-perfect — still
      // reaches the clipboard.
      try {
        const el = document.createElement("textarea");
        el.value = address;
        el.setAttribute("readonly", "");
        el.style.position = "fixed";
        el.style.opacity = "0";
        document.body.appendChild(el);
        el.select();
        ok = document.execCommand("copy");
        document.body.removeChild(el);
      } catch {
        ok = false;
      }
    }
    if (ok) {
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    }
  };

  return (
    <button
      onClick={copy}
      title="Copy contract address"
      aria-label={`Copy contract address ${address}`}
      className="group inline-flex items-center gap-2 font-mono text-[11px] tracking-label
        text-muted hover:text-cream transition-colors max-w-full"
    >
      <span className="text-orange shrink-0">{label} —</span>
      <span className="truncate">{address}</span>
      <span className="shrink-0 text-faint group-hover:text-orange transition-colors">
        {copied ? "copied ✓" : "copy"}
      </span>
    </button>
  );
}
