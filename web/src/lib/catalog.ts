import type { MediaType } from "./types";

export const MOVIE_GENRES: Record<number, string> = {
  28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime", 99: "Documentary",
  18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History", 27: "Horror", 10402: "Music",
  9648: "Mystery", 10749: "Romance", 878: "Sci-Fi", 53: "Thriller", 10752: "War", 37: "Western",
  10770: "TV Movie",
};

export const TV_GENRES: Record<number, string> = {
  10759: "Action & Adventure", 16: "Animation", 35: "Comedy", 80: "Crime", 99: "Documentary",
  18: "Drama", 10751: "Family", 10762: "Kids", 9648: "Mystery", 10763: "News", 10764: "Reality",
  10765: "Sci-Fi & Fantasy", 10766: "Soap", 10767: "Talk", 10768: "War & Politics", 37: "Western",
};

export function genreName(id: number): string | undefined {
  return MOVIE_GENRES[id] ?? TV_GENRES[id];
}

/** Moods from `MoodDiscoveryView.swift`, mapped to TMDB genres for each vocabulary. */
export interface Mood {
  slug: string;
  name: string;
  emoji: string;
  subtitle: string;
  movie: { with_genres?: string; without_genres?: string; "primary_release_date.lte"?: string };
  tv: { with_genres?: string; without_genres?: string; "first_air_date.lte"?: string; with_keywords?: string };
}

export const MOODS: Mood[] = [
  { slug: "feel-good", name: "Feel-Good", emoji: "☀️", subtitle: "Uplifting & heartwarming", movie: { with_genres: "35,10751", without_genres: "27" }, tv: { with_genres: "35|10751" } },
  { slug: "edge-of-seat", name: "Edge of My Seat", emoji: "🔥", subtitle: "Thrilling & intense", movie: { with_genres: "28|53" }, tv: { with_genres: "10759|80" } },
  { slug: "mind-bending", name: "Mind-Bending", emoji: "🧠", subtitle: "Twisty & thought-provoking", movie: { with_genres: "878|9648" }, tv: { with_genres: "10765|9648" } },
  { slug: "cozy", name: "Cozy Night In", emoji: "🌙", subtitle: "Relaxing & easy-going", movie: { with_genres: "10749|35", without_genres: "27,53" }, tv: { with_genres: "35", without_genres: "80" } },
  { slug: "epic", name: "Epic Adventure", emoji: "⚔️", subtitle: "Grand scale & fantastical", movie: { with_genres: "12|14" }, tv: { with_genres: "10759|10765" } },
  { slug: "laugh", name: "Laugh Out Loud", emoji: "😂", subtitle: "Hilarious comedies", movie: { with_genres: "35" }, tv: { with_genres: "35" } },
  { slug: "dark", name: "Dark & Gritty", emoji: "🌑", subtitle: "Crime, noir & moral grey", movie: { with_genres: "80|53" }, tv: { with_genres: "80" } },
  { slug: "cry", name: "Cry It Out", emoji: "💧", subtitle: "Emotional & moving dramas", movie: { with_genres: "18", without_genres: "35" }, tv: { with_genres: "18", without_genres: "35" } },
  { slug: "spooky", name: "Spooky", emoji: "👻", subtitle: "Horror & the uncanny", movie: { with_genres: "27" }, tv: { with_keywords: "8087|315058", with_genres: "9648|10765" } },
  { slug: "nostalgia", name: "Nostalgia Trip", emoji: "📼", subtitle: "Classics & retro favorites", movie: { "primary_release_date.lte": "1999-12-31" }, tv: { "first_air_date.lte": "1999-12-31" } },
  { slug: "family", name: "Family Night", emoji: "🍿", subtitle: "Something for every age", movie: { with_genres: "10751|16" }, tv: { with_genres: "10751|10762" } },
  { slug: "true-story", name: "True Story", emoji: "📰", subtitle: "Docs & real events", movie: { with_genres: "99|36" }, tv: { with_genres: "99" } },
];

/** Default streaming services from `MyStreamingView.swift`, with current TMDB ids and logos. */
export const SERVICES = [
  { id: 8, name: "Netflix", logo: "/rK1KljqmbvO9HQa1PBFLILWah72.png" },
  { id: 337, name: "Disney+", logo: "/5eZ872CghnHFLB1j8grszbrx0dx.png" },
  { id: 1899, name: "HBO Max", logo: "/skypuy7SXuugIQeYg0IglmzoKaS.png" },
  { id: 9, name: "Prime Video", logo: "/gMZdpavHmxFNnLpMHwVxfqeux2g.png" },
  { id: 15, name: "Hulu", logo: "/44uAnmSqvA4yBOdbPWN8YgQHjWm.png" },
  { id: 2303, name: "Paramount+", logo: "/4N4BMd0Mm0kHAmF7RZgL5lW3cwc.png" },
  { id: 386, name: "Peacock", logo: "/a1UIdq5BrkcAxnxcUhFsNbXnxeu.png" },
  { id: 350, name: "Apple TV", logo: "/9icYBfYFcwgCbky5VdGUIKJ4C5i.png" },
  { id: 283, name: "Crunchyroll", logo: "/uFL3c4Cq8M6WoLymlC5Y8bmGytV.png" },
  { id: 73, name: "Tubi", logo: "/9dEuvA8wg5TSeFBZlPxSVxFdimJ.png" },
  { id: 300, name: "Pluto TV", logo: "/fN4czqaMQNLeF6sSSIjGbAWzvwK.png" },
  { id: 43, name: "Starz", logo: "/h25xjouKmiSmFiiqw0aDXbxGZo7.png" },
  { id: 11, name: "MUBI", logo: "/k7iSlvgWzZuO4zU5PcBjhABMuia.png" },
  { id: 99, name: "Shudder", logo: "/58O6yqUFM6qoOiBNAddJs7xNKc.png" },
  { id: 151, name: "BritBox", logo: "/eZeWGG6DDIi4Kmu1z9RfTeZtqZX.png" },
];

export const REGIONS: { code: string; name: string }[] = [
  { code: "US", name: "United States" }, { code: "GB", name: "United Kingdom" }, { code: "ZA", name: "South Africa" },
  { code: "CA", name: "Canada" }, { code: "AU", name: "Australia" }, { code: "NZ", name: "New Zealand" },
  { code: "IE", name: "Ireland" }, { code: "IN", name: "India" }, { code: "DE", name: "Germany" },
  { code: "FR", name: "France" }, { code: "ES", name: "Spain" }, { code: "IT", name: "Italy" },
  { code: "NL", name: "Netherlands" }, { code: "SE", name: "Sweden" }, { code: "BR", name: "Brazil" },
  { code: "MX", name: "Mexico" }, { code: "JP", name: "Japan" }, { code: "KR", name: "South Korea" },
];

/** Studio and network hubs. `companies` feed /discover/movie, `networks` feed /discover/tv. */
export interface Hub {
  slug: string;
  name: string;
  tagline: string;
  color: string;
  companies?: number[];
  networks?: number[];
  tvCompanies?: number[];
}

export const HUBS: Hub[] = [
  { slug: "marvel", name: "Marvel", tagline: "Every hero, every phase", color: "#E62429", companies: [420], tvCompanies: [420, 38679] },
  { slug: "dc", name: "DC", tagline: "Gods and monsters", color: "#0476F2", companies: [128064, 9993, 429], tvCompanies: [128064, 9993] },
  { slug: "pixar", name: "Pixar", tagline: "To infinity and beyond", color: "#1E88E5", companies: [3] },
  { slug: "disney", name: "Walt Disney Pictures", tagline: "Where dreams begin", color: "#113CCF", companies: [2] },
  { slug: "lucasfilm", name: "Lucasfilm", tagline: "A long time ago…", color: "#D4AF37", companies: [1], tvCompanies: [1] },
  { slug: "ghibli", name: "Studio Ghibli", tagline: "Hand-drawn wonder", color: "#5BA4CF", companies: [10342] },
  { slug: "a24", name: "A24", tagline: "Bold, strange, singular", color: "#E8E8E8", companies: [41077], tvCompanies: [41077] },
  { slug: "blumhouse", name: "Blumhouse", tagline: "Lights off", color: "#9B1C1C", companies: [3172] },
  { slug: "dreamworks", name: "DreamWorks Animation", tagline: "Boy on the moon", color: "#3BA3E5", companies: [521] },
  { slug: "netflix", name: "Netflix", tagline: "Originals", color: "#E50914", networks: [213] },
  { slug: "hbo", name: "HBO", tagline: "It's not TV", color: "#A78BFA", networks: [49, 3186] },
  { slug: "apple-tv", name: "Apple TV+", tagline: "Originals", color: "#F5F5F7", networks: [2552] },
  { slug: "disney-plus", name: "Disney+", tagline: "Originals", color: "#1A73E8", networks: [2739] },
  { slug: "prime", name: "Prime Video", tagline: "Originals", color: "#00A8E1", networks: [1024] },
  { slug: "hulu", name: "Hulu", tagline: "Originals", color: "#1CE783", networks: [453] },
  { slug: "fx", name: "FX", tagline: "Fearless", color: "#F5F5F5", networks: [88, 1035] },
];

export const hubBySlug = (slug: string) => HUBS.find((h) => h.slug === slug);

export const mediaLabel = (t: MediaType) => (t === "movie" ? "Movie" : "TV Show");
