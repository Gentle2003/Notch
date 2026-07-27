"use client";

import Image from "next/image";

/**
 * The Notch mascot. The artwork is a still, so the life comes from the frame:
 * a slow vertical float, a subtle breathing scale, and a pulsing orange aura
 * bleeding out from behind the panel. All of it is disabled under
 * prefers-reduced-motion (see globals.css).
 */
export function BadgerHero({ size = 340 }: { size?: number }) {
  return (
    <div
      className="relative shrink-0 group"
      style={{ width: size, height: size }}
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
        <div className="relative h-full w-full animate-breathe transition-transform duration-500 group-hover:scale-[1.06]">
          <Image
            src="/notch-badger.png"
            alt="Notch — the badger that digs for signal"
            width={size * 2}
            height={size * 2}
            quality={95}
            priority
            className="h-full w-full object-cover rounded-[3px] border border-orange/30 shadow-glow"
          />

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
    <span
      aria-hidden
      className={`absolute h-3 w-3 border-orange ${className}`}
    />
  );
}
