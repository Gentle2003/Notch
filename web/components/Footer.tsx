import Link from "next/link";
import { Logo } from "./Logo";
import { FooterCA } from "./FooterCA";

const X_URL = "https://x.com/notchmarket";

export function Footer() {
  return (
    <footer className="mt-24 border-t border-border pt-8 pb-4">
      <div className="flex flex-col-reverse gap-6 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-3">
          <Logo size={22} />
          <span className="text-[11px] text-muted tracking-label">
            Notch — stake on the signal, not the noise.
          </span>
        </div>

        <Link
          href={X_URL}
          target="_blank"
          rel="noreferrer"
          aria-label="Notch on X"
          title="Notch on X"
          className="flex h-9 w-9 items-center justify-center rounded-[3px] border border-border
            text-muted hover:text-orange hover:border-orange/50 transition-colors"
        >
          <svg viewBox="0 0 24 24" width="15" height="15" fill="currentColor" aria-hidden>
            <path d="M13.6 10.6 21 2h-1.8l-6.4 7.5L7.6 2H2l7.8 11.3L2 22h1.8l6.8-7.9L16 22h5.6l-8-11.4Zm-2.4 2.8-.8-1.1L4.4 3.3h2.7l5.1 7.3.8 1.1 6.6 9.4h-2.7l-5.4-7.7Z" />
          </svg>
        </Link>
      </div>

      <div className="mt-6 pt-6 border-t border-border/60">
        <FooterCA />
      </div>

      <div className="mt-6 text-[11px] text-faint leading-relaxed max-w-3xl">
        Testnet only. NOTCH is a valueless test token on Robinhood Chain testnet and nothing
        here is investment advice. Markets resolve on staked consensus, not on truth — a
        large enough staker can move any outcome.
      </div>
    </footer>
  );
}
