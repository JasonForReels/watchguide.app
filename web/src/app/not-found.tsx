import Link from "next/link";

export default function NotFound() {
  return (
    <div className="mx-auto max-w-md px-4 py-24 text-center">
      <div className="marquee-bulbs mx-auto mb-6 w-24" aria-hidden="true" />
      <p className="font-display text-6xl font-black text-accent">404</p>
      <h1 className="mt-3 font-display text-2xl font-semibold">This reel is missing</h1>
      <p className="mt-2 text-muted">We couldn&apos;t find that page or title.</p>
      <Link href="/" className="mt-6 inline-block rounded-full bg-accent px-5 py-2.5 text-sm font-semibold text-on-accent">Back to Browse</Link>
    </div>
  );
}
