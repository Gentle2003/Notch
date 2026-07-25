import { fmtToken } from "@/lib/format";

export function ConsensusBar({
  yesStake,
  noStake,
}: {
  yesStake: bigint;
  noStake: bigint;
}) {
  const total = yesStake + noStake;
  const yesPct = total === 0n ? 50 : Number((yesStake * 10000n) / total) / 100;

  return (
    <div>
      <div className="flex justify-between text-xs mb-1.5">
        <span className="text-lime font-semibold">{yesPct.toFixed(0)}% signal</span>
        <span className="text-no font-semibold">{(100 - yesPct).toFixed(0)}% noise</span>
      </div>
      <div className="h-2 rounded-full bg-no/30 overflow-hidden">
        <div
          className="h-full bg-lime rounded-full transition-all"
          style={{ width: `${yesPct}%` }}
        />
      </div>
      <div className="flex justify-between text-[11px] text-muted mt-1.5">
        <span>{fmtToken(yesStake)} staked YES</span>
        <span>{fmtToken(noStake)} staked NO</span>
      </div>
    </div>
  );
}
