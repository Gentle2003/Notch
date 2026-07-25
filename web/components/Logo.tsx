export function Logo({ size = 28 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" fill="none" aria-hidden>
      <rect width="32" height="32" rx="8" fill="#141619" stroke="#2a2e35" />
      {/* a "notch" cut into a rising bar */}
      <path
        d="M8 22V14l4-2 4 3 4-6 4 4"
        stroke="#ccff00"
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle cx="24" cy="10" r="1.8" fill="#ccff00" />
    </svg>
  );
}
