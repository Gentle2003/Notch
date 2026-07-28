"use client";

import Link from "next/link";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Logo } from "./Logo";

export function Header() {
  return (
    <header className="flex items-center justify-between py-5">
      <div className="flex items-center gap-8">
        <Link href="/" className="flex items-center gap-2.5">
          <Logo />
          <span className="text-lg font-bold tracking-tight">
            Notch<span className="text-orange">.</span>
          </span>
        </Link>
        <nav className="hidden gap-6 text-sm text-muted sm:flex">
          <Link href="/" className="hover:text-white transition">
            Datanets
          </Link>
          <Link href="/submit" className="hover:text-white transition">
            Submit
          </Link>
          <Link href="/leaderboard" className="hover:text-white transition">
            Leaderboard
          </Link>
        </nav>
      </div>
      <ConnectButton
        // No standing chain pill — the network lives behind the account button
        // instead of taking up header space. RainbowKit still swaps in a
        // "Wrong network" button on its own if the wallet is on an unsupported chain.
        chainStatus="none"
        accountStatus={{ smallScreen: "avatar", largeScreen: "full" }}
        showBalance={false}
      />
    </header>
  );
}
