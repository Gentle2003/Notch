import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Warm near-black canvas + cream, with the badger banner's exact orange.
        canvas: "#080808",
        surface: "#111111",
        "surface-2": "#141210",
        border: "#2a2521",
        cream: "#f0ede6",
        muted: "#9d948d",
        faint: "#66625c",
        // Sampled directly from notch-badger-banner.png (dominant bg = #fa5101)
        orange: {
          DEFAULT: "#fa5101",
          text: "#fa5101", // 6.0:1 on canvas — passes AA for body text
          dim: "#d64400", // hover / pressed
          fur: "#f75802", // badger fur highlight
        },
        // two-sided market: signal = brand orange, noise = warm stone
        yes: "#fa5101",
        no: "#8c8279",
      },
      fontFamily: {
        mono: ["var(--font-mono)", "IBM Plex Mono", "monospace"],
        serif: ["var(--font-serif)", "Georgia", "serif"],
        sans: ["var(--font-mono)", "IBM Plex Mono", "monospace"],
      },
      letterSpacing: {
        label: "0.06em",
      },
      boxShadow: {
        glow: "0 0 28px rgba(250,81,1,0.18)",
      },
      keyframes: {
        float: {
          "0%, 100%": { transform: "translateY(0) rotate(-0.4deg)" },
          "50%": { transform: "translateY(-14px) rotate(0.4deg)" },
        },
        breathe: {
          "0%, 100%": { transform: "scale(1)" },
          "50%": { transform: "scale(1.025)" },
        },
        auraPulse: {
          "0%, 100%": { opacity: "0.35", transform: "scale(1)" },
          "50%": { opacity: "0.6", transform: "scale(1.08)" },
        },
        blink: {
          "0%, 92%, 100%": { opacity: "0" },
          "94%, 98%": { opacity: "1" },
        },
      },
      animation: {
        float: "float 6s ease-in-out infinite",
        breathe: "breathe 4s ease-in-out infinite",
        aura: "auraPulse 5s ease-in-out infinite",
        blink: "blink 7s ease-in-out infinite",
      },
    },
  },
  plugins: [],
};

export default config;
