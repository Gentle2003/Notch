import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { Providers } from "./providers";
import { Header } from "@/components/Header";

const inter = Inter({ subsets: ["latin"], variable: "--font-inter" });

export const metadata: Metadata = {
  title: "Notch — stake on the signal",
  description:
    "A research-quality staking market on Robinhood Chain. Researchers stake on their analysis; expert reviewers stake to grade it; the best earn reputation.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={inter.variable}>
      <body className="min-h-screen">
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
