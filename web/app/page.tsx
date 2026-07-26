"use client";

import Link from "next/link";
import Image from "next/image";
import { useDatanets, useArtifacts } from "@/lib/reads";
import { fmtToken } from "@/lib/format";
import { ArtifactCard } from "@/components/ArtifactCard";

export default function Home() {
  const { datanets } = useDatanets();
  const { artifacts } = useArtifacts();

  const countFor = (id: number) => artifacts.filter((a) => a.datanetId === id).length;
  const recent = [...artifacts].reverse().slice(0, 6);

  return (
    <main className="space-y-14">
      {/* Hero */}
      <section className="pt-10 pb-6 grid lg:grid-cols-[1fr_auto] gap-10 items-center">
        <div>
          <div className="eyebrow mb-6">
            <span className="text-orange">●</span> Live on Robinhood Chain — RWA × Meme research
          </div>
          <h1 className="display text-5xl sm:text-6xl leading-[1.02]">
            Stake on the <span className="em-serif">signal</span>,
            <br className="hidden sm:block" /> not the noise.
          </h1>
          <p className="text-muted mt-6 max-w-xl leading-relaxed">
            Notch is a research-quality market. Analysts stake on their RWA &amp; meme theses;
            expert reviewers stake to grade them. The crowd&apos;s capital prices the
            truth — and the sharpest analysts earn on-chain reputation.
          </p>
          <div className="flex gap-3 mt-8">
            <Link href="/submit" className="btn-primary">
              Submit research →
            </Link>
            <a href="#datanets" className="btn-outline-orange">
              Explore datanets
            </a>
          </div>
        </div>

        {/* Badger mascot */}
        <div className="hidden lg:block relative w-[320px] h-[320px] shrink-0">
          <Image
            src="/notch-badger.png"
            alt="Notch — the badger that digs for signal"
            fill
            sizes="320px"
            priority
            className="object-cover rounded-[3px] border border-border"
          />
        </div>
      </section>

      {/* How it works */}
      <section className="grid sm:grid-cols-3 gap-4">
        {[
          {
            n: "01",
            t: "Stake to submit",
            d: "A researcher posts an analysis and stakes NOTCH on it being high-signal. Skin in the game — no free spam.",
          },
          {
            n: "02",
            t: "Experts stake to judge",
            d: "Reviewers stake YES (signal) or NO (noise). Higher-trust datanets are gated by earned reputation.",
          },
          {
            n: "03",
            t: "Market resolves",
            d: "When the window closes, the heavier side wins. Losers are slashed, winners split the pool and earn Reps.",
          },
        ].map((s) => (
          <div key={s.n} className="card p-5">
            <div className="text-orange font-mono text-sm mb-2">{s.n}</div>
            <div className="font-semibold mb-1.5">{s.t}</div>
            <p className="text-sm text-muted leading-relaxed">{s.d}</p>
          </div>
        ))}
      </section>

      {/* Datanets */}
      <section id="datanets" className="scroll-mt-6">
        <div className="flex items-baseline justify-between mb-4">
          <h2 className="display text-3xl">Datanets</h2>
          <span className="eyebrow">{datanets.length} markets</span>
        </div>
        {datanets.length === 0 ? (
          <EmptyHint />
        ) : (
          <div className="grid sm:grid-cols-2 gap-4">
            {datanets.map((d) => (
              <Link
                key={d.id}
                href={`/datanet/${d.id}`}
                className="card p-5 hover:border-orange/40 transition group"
              >
                <div className="flex items-center justify-between mb-2">
                  <h3 className="font-semibold group-hover:text-orange transition">{d.name}</h3>
                  {d.minReviewerRep > 0n && (
                    <span className="pill bg-orange/10 text-orange">
                      🔒 {d.minReviewerRep.toString()} Reps
                    </span>
                  )}
                </div>
                <p className="text-sm text-muted leading-relaxed mb-4">{d.description}</p>
                <div className="flex justify-between text-xs text-muted pt-3 border-t border-border">
                  <span>{countFor(d.id)} artifacts</span>
                  <span>min {fmtToken(d.minSubmitStake)} NOTCH to submit</span>
                </div>
              </Link>
            ))}
          </div>
        )}
      </section>

      {/* Recent artifacts */}
      {recent.length > 0 && (
        <section>
          <h2 className="display text-3xl mb-4">Latest research</h2>
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {recent.map((a) => (
              <ArtifactCard
                key={a.id}
                a={a}
                datanetName={datanets.find((d) => d.id === a.datanetId)?.name}
              />
            ))}
          </div>
        </section>
      )}
    </main>
  );
}

function EmptyHint() {
  return (
    <div className="card p-8 text-center text-muted">
      <p className="mb-1">No datanets found on this network.</p>
      <p className="text-sm">
        Connect to Robinhood Chain (or run a local Anvil deploy) to see live markets.
      </p>
    </div>
  );
}
