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
        // Robinhood-inspired dark + lime accent
        canvas: "#0a0b0d",
        surface: "#141619",
        "surface-2": "#1c1f24",
        border: "#2a2e35",
        lime: {
          DEFAULT: "#ccff00",
          dim: "#a8d400",
        },
        yes: "#ccff00",
        no: "#ff5c72",
        muted: "#8a919e",
      },
      fontFamily: {
        sans: ["var(--font-inter)", "system-ui", "sans-serif"],
        mono: ["ui-monospace", "SFMono-Regular", "monospace"],
      },
      boxShadow: {
        glow: "0 0 24px rgba(204,255,0,0.15)",
      },
    },
  },
  plugins: [],
};

export default config;
