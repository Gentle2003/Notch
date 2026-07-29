import { fmtToken } from "@/lib/format";

/**
 * Shows where a thesis stands.
 *
 * The bar tracks *reputation-weighted* stake, because that is what decides the
 * outcome — showing raw NOTCH would tell people the wrong story about who is
 * winning. Raw stake is still shown underneath, since that is what determines
 * the payouts.
 */
export function ConsensusBar({
  yesStake,
  noStake,
  effectiveYes,
  effectiveNo,
}: {
  yesStake: bigint;
  noStake: bigint;
  effectiveYes?: bigint;
  effectiveNo?: bigint;
}) {
  // Fall back to raw stake for artifacts written before weighting existed.
  const wYes = effectiveYes ?? yesStake;
  const wNo = effectiveNo ?? noStake;
  const weightedTotal = wYes + wNo;
  const yesPct = weightedTotal === 0n ? 50 : Number((wYes * 10000n) / weightedTotal) / 100;

  // Whether reputation is actually moving the result, or the two views agree.
  const rawTotal = yesStake + noStake;
  const rawPct = rawTotal === 0n ? 50 : Number((yesStake * 10000n) / rawTotal) / 100;
  const repIsShiftingIt = rawTotal > 0n && Math.abs(yesPct - rawPct) >= 1;

  return (
    <div>
      <div className="flex justify-between text-xs mb-1.5">
        <span className="text-orange font-semibold">{yesPct.toFixed(0)}% signal</span>
        <span className="text-no font-semibold">{(100 - yesPct).toFixed(0)}% noise</span>
      </div>
      <div className="h-2 rounded-[2px] bg-no/25 overflow-hidden">
        <div
          className="h-full bg-orange rounded-[2px] transition-all duration-500"
          style={{ width: `${yesPct}%` }}
        />
      </div>
      <div className="flex justify-between text-[11px] text-muted mt-1.5">
        <span>{fmtToken(yesStake)} staked YES</span>
        <span>{fmtToken(noStake)} staked NO</span>
      </div>
      {repIsShiftingIt && (
        <div className="text-[11px] text-faint mt-1.5">
          Weighted by reviewer reputation — raw stake alone would read{" "}
          {rawPct.toFixed(0)}% signal.
        </div>
      )}
    </div>
  );
}
