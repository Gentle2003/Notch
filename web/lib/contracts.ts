import type { Address } from "viem";

/**
 * Deployed contract addresses per chainId.
 *
 * - 31337: deterministic Anvil deploy (deployer nonce 0..) — matches
 *   `forge script Deploy` on a fresh Anvil, so local dev works out of the box.
 * - 46630: Robinhood Chain testnet — filled in after `pnpm deploy:testnet`.
 */
export type Deployment = {
  NotchMarket: Address;
  NotchToken: Address;
  Reputation: Address;
};

export const deployments: Record<number, Deployment> = {
  31337: {
    NotchToken: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    Reputation: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
    NotchMarket: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
  },
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
