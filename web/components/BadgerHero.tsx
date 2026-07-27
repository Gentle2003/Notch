"use client";

import Image from "next/image";
import { useCallback, useEffect, useRef, useState } from "react";

/** How long the badger ponders before it settles on an answer. */
const THINK_MS = 2200;

/**
 * The Notch mascot, in two frames.
 *
 * On load he shows up mid-thought — paw on chin, eyes up — then resolves into
 * the confident, arms-folded pose and stays there. Hovering replays the beat.
 * Ambient motion (float, breathe, aura, sheen) runs underneath the whole time.
 *
 * Everything is stilled for `prefers-reduced-motion`: those visitors get the
 * confident frame immediately and no replay.
 */
export function BadgerHero({ size = 340 }: { size?: number }) {
  const [thinking, setThinking] = useState(true);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const reduced = useRef(false);

  useEffect(() => {
    reduced.current = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced.current) {
      setThinking(false);
      return;
    }
    timer.current = setTimeout(() => setThinking(false), THINK_MS);
    return () => {
      if (timer.current) clearTimeout(timer.current);
    };
  }, []);

  const replay = useCallback(() => {
    if (reduced.current) return;
    if (timer.current) clearTimeout(timer.current);
    setThinking(true);
    timer.current = setTimeout(() => setThinking(false), THINK_MS);
  }, []);

  return (
    <div
      className="relative shrink-0 group"
      style={{ width: size, height: size }}
      onMouseEnter={replay}
    >
      {/* pulsing aura behind the panel */}
      <div
        aria-hidden
        className="absolute -inset-10 animate-aura rounded-full blur-3xl pointer-events-none"
        style={{
          background:
            "radial-gradient(circle, rgba(250,81,1,0.55) 0%, rgba(250,81,1,0.12) 45%, transparent 70%)",
        }}
      />

      {/* floating frame */}
      <div className="relative h-full w-full animate-float">
        <div
          className={`relative h-full w-full animate-breathe overflow-hidden rounded-[3px]
            border border-orange/30 bg-orange shadow-glow transition-transform duration-500
            group-hover:scale-[1.06] ${thinking ? "" : "settle"}`}
        >
          {/* confident frame (base layer) */}
          <Image
            src="/notch-badger.jpg"
            alt="Notch — the badger that digs for signal"
            width={size * 2}
            height={size * 2}
            quality={95}
            priority
            className="h-full w-full object-cover"
          />

          {/* thinking frame, crossfaded on top */}
          <Image
            src="/notch-badger-thinking.jpg"
            alt=""
            aria-hidden
            width={size * 2}
            height={size * 2}
            quality={95}
            priority
            className={`absolute inset-0 h-full w-full object-cover transition-opacity
              duration-[550ms] ease-in-out ${thinking ? "opacity-100" : "opacity-0"}`}
          />

          {/* thought marks — only while he's puzzling it out */}
          <div
            aria-hidden
            className={`pointer-events-none absolute right-5 top-4 flex items-end gap-1
              transition-opacity duration-300 ${thinking ? "opacity-100" : "opacity-0"}`}
          >
            <span className="think-dot h-1.5 w-1.5 rounded-full bg-black/70" />
            <span className="think-dot h-2.5 w-2.5 rounded-full bg-black/70" />
            <span className="think-dot font-serif text-2xl leading-none text-black/80">?</span>
          </div>

          {/* scanline sheen sweeping across the panel */}
          <div
            aria-hidden
            className="pointer-events-none absolute inset-0 overflow-hidden rounded-[3px]"
          >
            <div className="sheen absolute inset-y-0 -left-1/2 w-1/2" />
          </div>
        </div>
      </div>

      {/* corner ticks — small mono-brutalist detail */}
      <Tick className="-top-px -left-px border-l border-t" />
      <Tick className="-top-px -right-px border-r border-t" />
      <Tick className="-bottom-px -left-px border-l border-b" />
      <Tick className="-bottom-px -right-px border-r border-b" />
    </div>
  );
}

function Tick({ className }: { className: string }) {
  return (
    <span aria-hidden className={`absolute h-3 w-3 border-orange ${className}`} />
  );
}
