export type MediaType = "movie" | "tv";

/** A movie, show or person as TMDB returns it in lists and search. */
export interface MediaItem {
  id: number;
  media_type?: MediaType | "person";
  title?: string;
  name?: string;
  poster_path?: string | null;
  backdrop_path?: string | null;
  profile_path?: string | null;
  overview?: string;
  release_date?: string;
  first_air_date?: string;
  vote_average?: number;
  vote_count?: number;
  popularity?: number;
  genre_ids?: number[];
  known_for_department?: string;
  original_language?: string;
}

export interface Paged<T> {
  page: number;
  results: T[];
  total_pages: number;
  total_results: number;
}

export interface Genre {
  id: number;
  name: string;
}

export interface CastMember {
  id: number;
  name: string;
  character?: string;
  job?: string;
  profile_path?: string | null;
  order?: number;
}

export interface Video {
  key: string;
  name: string;
  site: string;
  type: string;
  official?: boolean;
}

export interface Provider {
  provider_id: number;
  provider_name: string;
  logo_path: string;
  display_priority?: number;
}

export interface RegionProviders {
  link?: string;
  flatrate?: Provider[];
  rent?: Provider[];
  buy?: Provider[];
  free?: Provider[];
  ads?: Provider[];
}

export interface SeasonSummary {
  id: number;
  season_number: number;
  name: string;
  episode_count: number;
  air_date?: string | null;
  poster_path?: string | null;
}

export interface Episode {
  id: number;
  episode_number: number;
  season_number: number;
  name: string;
  overview?: string;
  air_date?: string | null;
  runtime?: number | null;
  still_path?: string | null;
  vote_average?: number;
  vote_count?: number;
}

export interface SeasonDetails {
  id: number;
  season_number: number;
  name: string;
  overview?: string;
  episodes: Episode[];
}

export interface TitleDetails {
  id: number;
  title?: string;
  name?: string;
  tagline?: string;
  overview?: string;
  poster_path?: string | null;
  backdrop_path?: string | null;
  release_date?: string;
  first_air_date?: string;
  last_air_date?: string;
  runtime?: number;
  episode_run_time?: number[];
  number_of_seasons?: number;
  number_of_episodes?: number;
  status?: string;
  in_production?: boolean;
  vote_average?: number;
  vote_count?: number;
  genres?: Genre[];
  seasons?: SeasonSummary[];
  belongs_to_collection?: { id: number; name: string; poster_path?: string | null; backdrop_path?: string | null } | null;
  networks?: { id: number; name: string; logo_path?: string | null }[];
  production_companies?: { id: number; name: string; logo_path?: string | null }[];
  next_episode_to_air?: Episode | null;
  last_episode_to_air?: Episode | null;
  imdb_id?: string;
  budget?: number;
  revenue?: number;
  credits?: { cast: CastMember[]; crew: CastMember[] };
  videos?: { results: Video[] };
  recommendations?: Paged<MediaItem>;
  similar?: Paged<MediaItem>;
  images?: { logos: { file_path: string; iso_639_1: string | null }[] };
  "watch/providers"?: { results: Record<string, RegionProviders> };
  external_ids?: { imdb_id?: string };
  production_countries?: { iso_3166_1: string; name: string }[];
  origin_country?: string[];
  release_dates?: { results: { iso_3166_1: string; release_dates: { certification: string; type: number }[] }[] };
  content_ratings?: { results: { iso_3166_1: string; rating: string }[] };
}

export interface PersonDetails {
  id: number;
  name: string;
  biography?: string;
  birthday?: string | null;
  deathday?: string | null;
  place_of_birth?: string | null;
  profile_path?: string | null;
  known_for_department?: string;
  combined_credits?: { cast: (MediaItem & { character?: string })[]; crew: (MediaItem & { job?: string })[] };
}

export interface CollectionDetails {
  id: number;
  name: string;
  overview?: string;
  poster_path?: string | null;
  backdrop_path?: string | null;
  parts: MediaItem[];
}

/** What the browser keeps for a title on a list. Mirrors `SavedMediaItem` on iOS. */
export interface SavedItem {
  key: string; // "movie-123"
  id: number;
  type: MediaType;
  title: string;
  poster: string | null;
  backdrop: string | null;
  year: string | null;
  date: string | null;
  rating: number | null;
  overview: string | null;
  genres: number[];
  addedAt: number;
}
