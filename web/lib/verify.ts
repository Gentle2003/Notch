"use client";

import { useEffect, useState } from "react";
import { keccak256, toBytes } from "viem";

/**
 * Integrity states for an artifact's linked analysis.
 *
 * The chain can't fetch a URL, so `contentHash` is only a commitment made at
 * submission. Verification happens here: re-fetch, re-hash, compare.
 */
export type Integrity =
  | "checking"
  | "verified" // hash matches — content reads as it did when stakes were placed
  | "changed" // hash differs — content was edited after submission
  | "uncommitted" // submitter stored no hash (legacy artifact, or declined)
  | "unreachable"; // couldn't fetch — CORS, 404, offline. NOT proof of tampering.

export const ZERO_HASH =
  "0x0000000000000000000000000000000000000000000000000000000000000000";

export type SnapshotResult =
  | { ok: true; hash: `0x${string}` }
  | { ok: false; reason: "not-http" | "unreachable" | "http-error" | "unstable"; detail?: string };

/**
 * Fetch a source twice and hash both. A hash is only committed if the two agree.
 *
 * Most of the web is not hashable. Pages like x.com embed per-request tokens and
 * timestamps, so the same unedited page hashes differently on every fetch —
 * measured at three fetches, three hashes, with the byte count wobbling by one.
 * Committing one of those would mean every reviewer sees "content changed"
 * forever, which trains people to ignore the warning that is supposed to matter.
 *
 * Refusing to hash an unstable source is more honest than hashing it badly.
 */
export async function snapshot(uri: string): Promise<SnapshotResult> {
  if (!/^https?:\/\//.test(uri)) return { ok: false, reason: "not-http" };

  const fetchText = async () => {
    const res = await fetch(uri, { cache: "no-store" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.text();
  };

  let first: string;
  try {
    first = await fetchText();
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return msg.startsWith("HTTP")
      ? { ok: false, reason: "http-error", detail: msg }
      : { ok: false, reason: "unreachable" };
  }

  try {
    const second = await fetchText();
    if (hashContent(first) !== hashContent(second)) {
      return { ok: false, reason: "unstable" };
    }
  } catch {
    return { ok: false, reason: "unstable" };
  }

  return { ok: true, hash: hashContent(first) };
}

/** Hash raw text the same way the submit form does, so the two always agree. */
export function hashContent(text: string): `0x${string}` {
  return keccak256(toBytes(text));
}

/**
 * Fetch `uri` and compare its hash against the on-chain commitment.
 *
 * Many sources (Twitter/X in particular) send no CORS headers, so the browser
 * cannot read them and we land on "unreachable". That is deliberately a
 * separate state from "changed" — failing to check is not evidence of tampering,
 * and conflating them would cry wolf on most off-site links.
 */
export function useIntegrity(uri?: string, contentHash?: string): Integrity {
  const [state, setState] = useState<Integrity>("checking");

  useEffect(() => {
    let cancelled = false;

    if (!contentHash || contentHash === ZERO_HASH) {
      setState("uncommitted");
      return;
    }
    if (!uri || !/^https?:\/\//.test(uri)) {
      // ipfs:// and friends need a gateway; treat as not checkable here.
      setState("unreachable");
      return;
    }

    setState("checking");
    fetch(uri)
      .then((r) => (r.ok ? r.text() : Promise.reject(new Error(String(r.status)))))
      .then((text) => {
        if (cancelled) return;
        setState(hashContent(text) === contentHash.toLowerCase() ? "verified" : "changed");
      })
      .catch(() => {
        if (!cancelled) setState("unreachable");
      });

    return () => {
      cancelled = true;
    };
  }, [uri, contentHash]);

  return state;
}
