import type { MetadataRoute } from "next";

/** Makes WatchGuide installable on Android (Chrome, Samsung Internet, Edge) as a full-screen app. */
export default function manifest(): MetadataRoute.Manifest {
  return {
    id: "/",
    name: "WatchGuide",
    short_name: "WatchGuide",
    description: "Find what to watch tonight, track every show and film, and see where it's streaming.",
    start_url: "/",
    scope: "/",
    display: "standalone",
    background_color: "#000000",
    theme_color: "#000000",
    categories: ["entertainment", "lifestyle"],
    icons: [
      { src: "/icons/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/icons/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
      { src: "/icons/maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
    shortcuts: [
      { name: "Search", url: "/search", icons: [{ src: "/icons/icon-192.png", sizes: "192x192" }] },
      { name: "Tonight", url: "/tonight", icons: [{ src: "/icons/icon-192.png", sizes: "192x192" }] },
      { name: "Lists", url: "/lists", icons: [{ src: "/icons/icon-192.png", sizes: "192x192" }] },
    ],
  };
}
