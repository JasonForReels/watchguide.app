import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import { Suspense } from "react";
import { ActiveNav, Nav } from "@/components/nav";
import { LiquidGlass } from "@/components/liquid-glass";
import { PWA } from "@/components/pwa";
import { ThemeSync } from "@/components/theme-sync";
import { THEMES, themeCSS } from "@/lib/themes";
import "./globals.css";

const inter = Inter({ variable: "--font-inter", subsets: ["latin"] });

export const metadata: Metadata = {
  title: { default: "WatchGuide", template: "%s · WatchGuide" },
  description: "Find what to watch tonight, track every show and film, and see where it's streaming.",
  applicationName: "WatchGuide",
  appleWebApp: { capable: true, title: "WatchGuide", statusBarStyle: "black-translucent" },
  formatDetection: { telephone: false },
};

export const viewport: Viewport = {
  themeColor: "#000000",
  viewportFit: "cover",
};

/** Applies the saved theme before first paint so there's no flash of the default palette. */
const boot = `(function(){try{var s=JSON.parse(localStorage.getItem("watchguide.v1")||"{}").settings||{};var ids=${JSON.stringify(
  Object.fromEntries(THEMES.map((t) => [t.id, t.frame])),
)};var t=ids[s.theme]?s.theme:"marquee";var r=document.documentElement;r.dataset.theme=t;r.dataset.frame=ids[t];if(s.scheme&&s.scheme!=="system")r.dataset.scheme=s.scheme;}catch(e){}})();`;

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" data-theme="marquee" data-frame="marquee" className={`${inter.variable} antialiased`} suppressHydrationWarning>
      <head>
        <style dangerouslySetInnerHTML={{ __html: themeCSS() }} />
        <script dangerouslySetInnerHTML={{ __html: boot }} />
      </head>
      <body className="min-h-dvh">
        <ThemeSync />
        <PWA />
        <LiquidGlass />
        <Suspense fallback={<Nav />}>
          <ActiveNav />
        </Suspense>
        <main className="pb-32 md:pb-12">{children}</main>
      </body>
    </html>
  );
}
