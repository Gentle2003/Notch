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

// A public WalletConnect id works for local/testnet demos. Replace for production.
const projectId =
  process.env.NEXT_PUBLIC_WALLETCONNECT_ID ?? "3fbb6bba6f1de962d911bb5b5c9dba88";

// Curated wallet list — deliberately excludes the Coinbase/Base connector, which
// pulls in @coinbase/cdp-sdk + optional @x402/* packages that break the build.
const connectors = connectorsForWallets(
  [
    {
      groupName: "Popular",
      wallets: [injectedWallet, metaMaskWallet, rainbowWallet, walletConnectWallet],
    },
  ],
  { appName: "Notch", projectId },
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
