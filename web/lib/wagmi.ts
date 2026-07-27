"use client";

import { connectorsForWallets } from "@rainbow-me/rainbowkit";
import {
  injectedWallet,
  metaMaskWallet,
  rainbowWallet,
  walletConnectWallet,
} from "@rainbow-me/rainbowkit/wallets";
import { createConfig, http } from "wagmi";
import { robinhoodTestnet, robinhoodMainnet, anvil } from "./chains";

// WalletConnect / Reown project id. This is a PUBLIC identifier — it ships in the
// browser bundle regardless, so it lives in source and needs no env config.
// Override per-environment with NEXT_PUBLIC_WALLETCONNECT_ID.
const projectId =
  process.env.NEXT_PUBLIC_WALLETCONNECT_ID ?? "d7706add626b3a56770b7f4cad87fe0f";

const APP_URL =
  process.env.NEXT_PUBLIC_APP_URL ??
  "https://notch-web-gentlespreedev-4936s-projects.vercel.app";

// Curated wallet list — deliberately excludes the Coinbase/Base connector, which
// pulls in @coinbase/cdp-sdk + optional @x402/* packages that break the build.
//
// The Reown project is shared with another app, so we set app metadata explicitly:
// RainbowKit forwards these into the WalletConnect session, which is what wallets
// show on the approval screen. Without them, users would see the other project's
// name and icon when connecting to Notch.
const connectors = connectorsForWallets(
  [
    {
      groupName: "Popular",
      wallets: [injectedWallet, metaMaskWallet, rainbowWallet, walletConnectWallet],
    },
  ],
  {
    appName: "Notch",
    appDescription: "Stake on the signal, not the noise.",
    appUrl: APP_URL,
    appIcon: `${APP_URL}/notch-logo.jpg`,
    projectId,
  },
);

export const wagmiConfig = createConfig({
  chains: [robinhoodTestnet, anvil, robinhoodMainnet],
  connectors,
  transports: {
    [robinhoodTestnet.id]: http(),
    [anvil.id]: http(),
    [robinhoodMainnet.id]: http(),
  },
  ssr: true,
});
