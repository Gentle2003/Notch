import type { Metadata } from "next";
import { ArtifactView } from "@/components/ArtifactView";
import { fetchArtifactMeta, describeConsensus } from "@/lib/serverReads";

const SITE_URL = process.env.NEXT_PUBLIC_APP_URL ?? "https://www.notchmarket.xyz";

/**
 * Per-thesis link previews. Without this every shared artifact unfurled with the
 * same homepage card, so a researcher posting their thesis showed a generic
 * banner instead of the claim and its live consensus.
 */
export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}): Promise<Metadata> {
  const { id } = await params;
  const a = await fetchArtifactMeta(Number(id));

  if (!a) {
    return {
      title: "Thesis — Notch",
      description: "A research-quality staking market on Robinhood Chain.",
    };
  }

  const title = a.title;
  const description = describeConsensus(a);
  const url = `${SITE_URL}/artifact/${id}`;

  return {
    title: `${title} — Notch`,
    description,
    alternates: { canonical: `/artifact/${id}` },
    openGraph: {
      type: "article",
      siteName: "Notch",
      url,
      title,
      description,
    },
    twitter: { card: "summary_large_image", title, description },
  };
}

export default async function ArtifactPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return <ArtifactView id={Number(id)} />;
}
