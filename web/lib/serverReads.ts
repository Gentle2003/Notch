import { createPublicClient, http } from "viem";
import { robinhoodTestnet } from "./chains";
import { notchMarketAbi } from "./abis";
import { getDeployment } from "./contracts";

/**
 * Server-side chain reads, used by generateMetadata so a shared artifact link
 * unfurls with its actual thesis and live consensus. No wallet involved — this
 * runs at request time on the server, before any client JS.
 */
const CHAIN_ID = Number(process.env.NEXT_PUBLIC_DEFAULT_CHAIN ?? "46630");

const client = createPublicClient({
  chain: robinhoodTestnet,
  transport: http(),
});

export type ArtifactMeta = {
  title: string;
  submitter: string;
  yesStake: bigint;
  noStake: bigint;
  submitStake: bigint;
  status: number;
  outcomeYes: boolean;
  reviewDeadline: bigint;
};

export async function fetchArtifactMeta(id: number): Promise<ArtifactMeta | null> {
  const deployment = getDeployment(CHAIN_ID);
  if (!deployment) return null;

  try {
    const a = (await client.readContract({
      address: deployment.NotchMarket,
      abi: notchMarketAbi,
      functionName: "getArtifact",
      args: [BigInt(id)],
    })) as unknown as ArtifactMeta;
    return a;
  } catch {
    // Out-of-range id, RPC hiccup — fall back to generic metadata rather than 500.
    return null;
  }
}

/** "72% Signal · 1,060 NOTCH staked" — the hook that makes a share worth opening. */
export function describeConsensus(a: ArtifactMeta): string {
  const total = a.yesStake + a.noStake;
  const pct = total === 0n ? null : Number((a.yesStake * 10000n) / total) / 100;
  const staked = Number(total + a.submitStake) / 1e18;
  const amount = staked.toLocaleString(undefined, { maximumFractionDigits: 0 });

  if (a.status === 2) {
    return `${a.outcomeYes ? "Verified as signal" : "Rejected as noise"} · ${amount} NOTCH staked`;
  }
  if (pct === null) return `Open for review · ${amount} NOTCH at stake. Stake your read.`;
  return `${pct.toFixed(0)}% Signal · ${amount} NOTCH staked. Stake your read.`;
}
