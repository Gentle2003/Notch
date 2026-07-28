import Image from "next/image";

export function Logo({ size = 30 }: { size?: number }) {
  return (
    <Image
      src="/notch-logo-v2.jpg"
      alt="Notch badger"
      width={size}
      height={size}
      className="rounded-[4px] border border-border"
      priority
    />
  );
}
