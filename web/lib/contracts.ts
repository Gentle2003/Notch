import type { Address } from "viem";

/**
 * Deployed contract addresses per chainId.
 *
 * Robinhood Chain testnet (46630) only. A local Anvil entry (31337) used to live
 * here; it was dropped so the wallet's network list shows real networks only.
 * See git history if you need it back for local development.
 */
export type Deployment = {
  NotchMarket: Address;
  NotchToken: Address;
  Reputation: Address;
};

export const deployments: Record<number, Deployment> = {
  // Robinhood Chain testnet — deployed 2026-07-25
  46630: {
    NotchToken: "0xDc4d866c407521219B511e5d9e1AE583BB396674",
    Reputation: "0x984FBe6f007ea6Fd085E9A244F78cFC6b9705F4E",
    NotchMarket: "0x104540Cc7B00a42d98919bb2Ee16535F57541FD7",
  },
};

export function getDeployment(chainId: number | undefined): Deployment | null {
  if (!chainId) return null;
  return deployments[chainId] ?? null;
}
