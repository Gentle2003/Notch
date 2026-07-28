import type { Metadata } from "next";
import { IBM_Plex_Mono, Fraunces } from "next/font/google";
import "./globals.css";
import { Providers } from "./providers";
import { Header } from "@/components/Header";

const mono = IBM_Plex_Mono({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-mono",
});

const serif = Fraunces({
  subsets: ["latin"],
  style: ["normal", "italic"],
  variable: "--font-serif",
});

const SITE_URL = process.env.NEXT_PUBLIC_APP_URL ?? "https://www.notchmarket.xyz";

export const metadata: Metadata = {
  // Without this, the relative OG/Twitter image paths below can't be resolved
  // into the absolute URLs that social crawlers require.
  metadataBase: new URL(SITE_URL),
  title: "Notch — stake on the signal",
  description:
    "A research-quality staking market on Robinhood Chain. Researchers stake on their analysis; expert reviewers stake to grade it; the best earn reputation.",
  alternates: { canonical: "/" },
  icons: {
    icon: "/notch-logo.jpg",
    apple: "/notch-logo.jpg",
  },
  openGraph: {
    type: "website",
    siteName: "Notch",
    url: SITE_URL,
    title: "Notch — stake on the signal",
    description:
      "A research-quality staking market on Robinhood Chain. Stake on the signal, not the noise.",
    images: ["/notch-badger-banner.jpg"],
  },
  twitter: {
    card: "summary_large_image",
    title: "Notch — stake on the signal",
    description:
      "A research-quality staking market on Robinhood Chain. Stake on the signal, not the noise.",
    images: ["/notch-badger-banner.jpg"],
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={`${mono.variable} ${serif.variable}`}>
      <body className="min-h-screen font-mono">
        <Providers>
          <div className="mx-auto max-w-6xl px-4 pb-24">
            <Header />
            {children}
          </div>
        </Providers>
      </body>
    </html>
  );
}
