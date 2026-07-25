import { formatUnits } from "viem";

/** Format an 18-decimal token amount for display (e.g. "1,250"). */
export function fmtToken(v: bigint | undefined, decimals = 18, maxFrac = 2): string {
  if (v === undefined) return "—";
  const n = Number(formatUnits(v, decimals));
  return n.toLocaleString(undefined, { maximumFractionDigits: maxFrac });
}

export function shortAddr(a?: string): string {
  if (!a) return "";
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

export function bpsToPct(bps: bigint | number | undefined): number {
  if (bps === undefined) return 50;
  return Number(bps) / 100;
}

/** Relative time until (or since) a unix-seconds deadline. */
export function timeLeft(deadline: bigint | number | undefined): string {
  if (deadline === undefined) return "";
  const secs = Number(deadline) - Math.floor(Date.now() / 1000);
  if (secs <= 0) return "review closed";
  const d = Math.floor(secs / 86400);
  const h = Math.floor((secs % 86400) / 3600);
  const m = Math.floor((secs % 3600) / 60);
  if (d > 0) return `${d}d ${h}h left`;
  if (h > 0) return `${h}h ${m}m left`;
  return `${m}m left`;
}

export const STATUS = ["Reviewing", "Resolved"] as const;
