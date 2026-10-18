import type { Metadata } from "next";
import { dedupe, typeOf } from "@/lib/media";
import { list, tmdbSafe } from "@/lib/tmdb";
import type { Video } from "@/lib/types";
import { PopsFeed, type Pop } from "./pops-feed";

export const metadata: Metadata = { title: "Pops", description: "Trailers and clips from what everyone's watching." };

export const revalidate = 3600;

export default async function PopsPage() {
  const [day, week] = await Promise.all([list("trending/all/day"), list("trending/all/week")]);
  const items = dedupe([...day, ...week]).filter((i) => i.media_type !== "person" && i.backdrop_path).slice(0, 18);
  const pops = await Promise.all(
    items.map(async (item): Promise<Pop | null> => {
      const type = typeOf(item);
      const videos = await tmdbSafe<{ results: Video[] }>(`${type}/${item.id}/videos`);
      const yt = (videos?.results ?? []).filter((v) => v.site === "YouTube");
      const clip = yt.find((v) => v.type === "Trailer" && v.official) ?? yt.find((v) => v.type === "Trailer") ?? yt.find((v) => v.type === "Teaser") ?? yt[0];
      return clip ? { item, type, videoKey: clip.key, clipName: clip.name } : null;
    }),
  );

  return <PopsFeed pops={pops.filter((p): p is Pop => p !== null)} />;
}
