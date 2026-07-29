"use client";

import { useMemo } from "react";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import type { Address } from "viem";
import { notchMarketAbi } from "./abis";
import { getDeployment } from "./contracts";

/**
 * Which chain reads target. Uses the connected wallet's chain when available,
 * otherwise NEXT_PUBLIC_DEFAULT_CHAIN (so the site renders data pre-connect,
 * and local dev can point at Anvil).
 */
export function useTargetChain() {
  const { chainId: walletChain } = useAccount();
  // Defaults to Robinhood testnet (live network); local dev sets 31337 via .env.local.
  // Mainnet is the default so shared links resolve for visitors who have not
  // connected a wallet. Testnet has no artifacts, so defaulting there made every
  // shared link look permanently broken.
  const fallback = Number(process.env.NEXT_PUBLIC_DEFAULT_CHAIN ?? "4663");
  const chainId = walletChain ?? fallback;
  const deployment = getDeployment(chainId);
  return { chainId, deployment, market: deployment?.NotchMarket as Address | undefined };
}

export type Datanet = {
  id: number;
  name: string;
  description: string;
  minSubmitStake: bigint;
  reviewWindow: bigint;
  minReviewerRep: bigint;
  exists: boolean;
};

export type Artifact = {
  id: number;
  datanetId: number;
  submitter: Address;
  title: string;
  contentURI: string;
  contentHash: string; // keccak256 committed at submission; ZERO_HASH if none
  submitStake: bigint;
  reviewDeadline: bigint;
  yesStake: bigint;
  noStake: bigint;
  effectiveYes: bigint; // reputation-weighted, decides the outcome
  effectiveNo: bigint;
  status: number; // see STATUS below
  outcomeYes: boolean;
  submitterClaimed: boolean;
  challengeDeadline: bigint;
  round: number;
};

/**
 * resolve() posts a provisional outcome; it only becomes payable once the
 * challenge window elapses and someone finalises it.
 */
export const STATUS = { Reviewing: 0, Challengeable: 1, Final: 2 } as const;

export function useDatanetCount() {
  const { market, chainId } = useTargetChain();
  return useReadContract({
    address: market,
    abi: notchMarketAbi,
    functionName: "datanetCount",
    chainId,
    query: { enabled: !!market, refetchInterval: 8000 },
  });
}

export function useDatanets() {
  const { market, chainId } = useTargetChain();
  const { data: count } = useDatanetCount();
  const n = count ? Number(count) : 0;

  const contracts = useMemo(
    () =>
      Array.from({ length: n }, (_, i) => ({
        address: market as Address,
        abi: notchMarketAbi,
        functionName: "datanets" as const,
        args: [BigInt(i)] as const,
        chainId,
      })),
    [n, market, chainId],
  );

  const { data, isLoading } = useReadContracts({
    contracts,
    query: { enabled: !!market && n > 0, refetchInterval: 10000 },
  });

  const datanets: Datanet[] = useMemo(() => {
    if (!data) return [];
    return data.map((r, i) => {
      const t = r.result as unknown as [string, string, bigint, bigint, bigint, boolean];
      return {
        id: i,
        name: t[0],
        description: t[1],
        minSubmitStake: t[2],
        reviewWindow: t[3],
        minReviewerRep: t[4],
        exists: t[5],
      };
    });
  }, [data]);

  return { datanets, isLoading };
}

export function useArtifactCount() {
  const { market, chainId } = useTargetChain();
  return useReadContract({
    address: market,
    abi: notchMarketAbi,
    functionName: "artifactCount",
    chainId,
    query: { enabled: !!market, refetchInterval: 8000 },
  });
}

export function useArtifacts() {
  const { market, chainId } = useTargetChain();
  const { data: count } = useArtifactCount();
  const n = count ? Number(count) : 0;

  const contracts = useMemo(
    () =>
      Array.from({ length: n }, (_, i) => ({
        address: market as Address,
        abi: notchMarketAbi,
        functionName: "getArtifact" as const,
        args: [BigInt(i)] as const,
        chainId,
      })),
    [n, market, chainId],
  );

  const { data, isLoading, refetch } = useReadContracts({
    contracts,
    query: { enabled: !!market && n > 0, refetchInterval: 8000 },
  });

  const artifacts: Artifact[] = useMemo(() => {
    if (!data) return [];
    return data
      .map((r, i) => {
        const a = r.result as unknown as Artifact | undefined;
        if (!a) return null;
        return { ...a, id: i, datanetId: Number(a.datanetId) } as Artifact;
      })
      .filter((x): x is Artifact => x !== null);
  }, [data]);

  return { artifacts, isLoading, refetch };
}

export function useArtifact(id: number) {
  const { market, chainId } = useTargetChain();
  const { data, refetch, isLoading, isError } = useReadContract({
    address: market,
    abi: notchMarketAbi,
    functionName: "getArtifact",
    args: [BigInt(id)],
    chainId,
    query: { enabled: !!market, refetchInterval: 6000 },
  });
  const artifact = data
    ? ({ ...(data as unknown as Artifact), id, datanetId: Number((data as any).datanetId) } as Artifact)
    : undefined;
  // isError covers the out-of-bounds revert you get for an id that doesn't exist on
  // this chain — which is what a link shared from a different network looks like.
  return { artifact, refetch, isLoading, notFound: isError && !isLoading };
}
