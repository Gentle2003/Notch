import { ImageResponse } from "next/og";
import { fetchArtifactMeta } from "@/lib/serverReads";

export const alt = "Notch thesis";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

/**
 * Renders the share card for a single thesis: the claim itself, plus a signal
 * bar showing where the stake currently sits. Generated per request so the card
 * reflects live consensus rather than a stale snapshot.
 *
 * Deliberately no remote fonts or images — every fetch here is a chance to fail
 * and serve a broken card at exactly the moment someone shares the link.
 */
export default async function Image({ params }: { params: { id: string } }) {
  const a = await fetchArtifactMeta(Number(params.id));

  const title = a?.title ?? "Notch — stake on the signal";
  const total = a ? a.yesStake + a.noStake : 0n;
  const yesPct = !a || total === 0n ? null : Number((a.yesStake * 10000n) / total) / 100;
  const staked = a ? Number(total + a.submitStake) / 1e18 : 0;
  const resolved = a?.status === 1;

  const status = resolved
    ? a!.outcomeYes
      ? "VERIFIED AS SIGNAL"
      : "REJECTED AS NOISE"
    : "OPEN FOR REVIEW";

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          background: "#080808",
          padding: 64,
          fontFamily: "monospace",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
          <div style={{ width: 22, height: 22, background: "#fa5101", borderRadius: 4 }} />
          <div style={{ fontSize: 26, color: "#f0ede6", fontWeight: 700 }}>Notch</div>
          <div style={{ fontSize: 18, color: "#9d948d", letterSpacing: 2, marginLeft: 12 }}>
            {status}
          </div>
        </div>

        <div
          style={{
            fontSize: title.length > 90 ? 46 : 58,
            color: "#f0ede6",
            lineHeight: 1.2,
            display: "flex",
          }}
        >
          {title.length > 160 ? `${title.slice(0, 157)}…` : title}
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div style={{ display: "flex", width: "100%", height: 12, background: "#2a2521" }}>
            <div style={{ width: `${yesPct ?? 50}%`, height: "100%", background: "#fa5101" }} />
          </div>
          <div style={{ display: "flex", justifyContent: "space-between", fontSize: 24 }}>
            <div style={{ color: "#fa5101" }}>
              {yesPct === null ? "No reviews yet" : `${yesPct.toFixed(0)}% Signal`}
            </div>
            <div style={{ color: "#9d948d" }}>
              {`${staked.toLocaleString(undefined, { maximumFractionDigits: 0 })} NOTCH staked`}
            </div>
          </div>
        </div>
      </div>
    ),
    size,
  );
}
