export function Logo({ size = 28 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" fill="none" aria-hidden>
      <rect width="32" height="32" rx="3" fill="#141210" stroke="#262320" />
      {/* a "notch" cut into a rising bar */}
      <path
        d="M8 22V14l4-2 4 3 4-6 4 4"
        stroke="#f27a21"
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle cx="24" cy="10" r="1.8" fill="#f27a21" />
    </svg>
  );
}
