import type { Address } from "viem";

/**
 * Deployed contract addresses per chainId.
 *
 * Robinhood Chain mainnet (4663) and testnet (46630). A local Anvil entry (31337) used to live
 * here; it was dropped so the wallet's network list shows real networks only.
 * See git history if you need it back for local development.
 */
export type Deployment = {
  NotchMarket: Address;
  NotchToken: Address;
  Reputation: Address;
  /**
   * True while a deployment is a rehearsal rather than the real launch. The UI
   * refuses to present the collateral address as a contract address to buy when
   * this is set — an unlabelled CA is an implicit endorsement, and the current
   * mainnet collateral is a token whose own name says not to buy it.
   *
   * The launch script clears this when it points the app at the real token.
   */
  isTest?: boolean;
};

export const deployments: Record<number, Deployment> = {
  // Robinhood Chain mainnet. Collateral is whatever token the launch script
  // bound the market to — never one we mint. The launch script rewrites the
  // block below but not this comment, so keep it true of any deployment.
  4663: {
    NotchToken: "0xf840f342f11ef30fe3d018b76bbe77c164dab52b",
    Reputation: "0xc544114f4ecc4B7331D008b20550fF593C0835A0",
    NotchMarket: "0x468a2b93772D57cBB8D0ea7224eC2f274DfFdb36",
  },
  // Robinhood Chain testnet — v4, deployed 2026-07-28.
  // Adds escalating-bond appeals on top of reputation-weighted outcomes.
  46630: {
    NotchToken: "0x204d70a11d9315df3F2CbD7FAaA274918514ba61",
    Reputation: "0x5221B8Dc580321B2408218760f1F81603C798bE0",
    NotchMarket: "0x52C8a4D65aE2dd8ef2779180a0bbE714FB24b3BA",
  },
};

/**
 * Superseded deployments, newest first. Each was replaced because the Artifact
 * struct changed, which makes the ABI incompatible rather than merely outdated.
 *
 * They still hold live positions — notably v1 artifact #4, which has stake on it
 * and must be resolved and claimed against the v1 market, not the current one.
 * Balances do not carry across: each version has its own NOTCH token.
 * Kept for reference; the app does not read from them.
 */
export const legacyDeployments = [
  {
    version: "v3",
    NotchToken: "0xc6DB1897F88e5F527507eE4533927fC8e1117F97",
    Reputation: "0x046d3Fa756aB1263a23a8659B1743066C3E5697D",
    NotchMarket: "0x151A1179Ce9359b160e516f66Eab2f3c3EA428c7",
  },
  {
    version: "v2",
    NotchToken: "0xa4a1548F907F1d52c2311c3bA152DCC9F141e83C",
    Reputation: "0xfd97752096596EA8C84d17E353734E28aF2750b4",
    NotchMarket: "0x6ba36E1507685e6C40b440CA7119Fbf6DAC2Fa79",
  },
  {
    version: "v1",
    NotchToken: "0xDc4d866c407521219B511e5d9e1AE583BB396674",
    Reputation: "0x984FBe6f007ea6Fd085E9A244F78cFC6b9705F4E",
    NotchMarket: "0x104540Cc7B00a42d98919bb2Ee16535F57541FD7",
  },
] as const;

export function getDeployment(chainId: number | undefined): Deployment | null {
  if (!chainId) return null;
  return deployments[chainId] ?? null;
}
