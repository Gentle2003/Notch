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
  // 46630: filled after testnet deploy
};

export function getDeployment(chainId: number | undefined): Deployment | null {
  if (!chainId) return null;
  return deployments[chainId] ?? null;
}
