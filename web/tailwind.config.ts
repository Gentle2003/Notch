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
        // ClawBank-inspired: warm near-black + cream + orange
        canvas: "#080808",
        surface: "#111111",
        "surface-2": "#141210",
        border: "#262320",
        cream: "#f0ede6",
        muted: "#9d948d",
        faint: "#66625c",
        orange: {
          DEFAULT: "#f27a21", // solid buttons
          text: "#eb6e12", // orange text/emphasis
          dim: "#c85f14",
        },
        gold: "#c8a97e",
        // two-sided market — signal (orange) vs noise (rust)
        yes: "#f27a21",
        no: "#c85338",
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
        glow: "0 0 28px rgba(242,122,33,0.16)",
      },
    },
  },
  plugins: [],
};

export default config;
