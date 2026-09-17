# Supabase Setup for WatchGuide

## Database Schema

Run this SQL in your Supabase SQL Editor (SQL Editor → New Query):

```sql
-- ===================================================
-- WatchGuide Cloud Sync — Full Schema
-- ===================================================

-- 1. Media Items (watchlist, watched, liked)
CREATE TABLE IF NOT EXISTS media_items (
    id SERIAL PRIMARY KEY,
    device_id TEXT NOT NULL,
    list_type TEXT NOT NULL CHECK (list_type IN ('want_to_watch', 'watched', 'liked')),
    media_id INTEGER NOT NULL,
    media_type TEXT NOT NULL CHECK (media_type IN ('movie', 'tv')),
    title TEXT NOT NULL,
    poster_path TEXT,
    backdrop_path TEXT,
    year TEXT,
    vote_average DOUBLE PRECISION,
    overview TEXT,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(device_id, list_type, media_id, media_type)
);
CREATE INDEX IF NOT EXISTS idx_media_items_device ON media_items(device_id);
CREATE INDEX IF NOT EXISTS idx_media_items_list ON media_items(device_id, list_type);
CREATE INDEX IF NOT EXISTS idx_media_items_added ON media_items(added_at DESC);

ALTER TABLE media_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON media_items FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON media_items FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 2. User Settings (includes hero carousel custom/MDBList IDs)
CREATE TABLE IF NOT EXISTS user_settings (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE,
    region TEXT DEFAULT 'US',
    preferred_language TEXT DEFAULT 'en',
    include_adult BOOLEAN DEFAULT FALSE,
    auto_play_trailers BOOLEAN DEFAULT FALSE,
    auto_play_trailers_muted BOOLEAN DEFAULT TRUE,
    compact_mode BOOLEAN DEFAULT FALSE,
    ambient_mode_enabled BOOLEAN DEFAULT FALSE,
    hero_carousel_source TEXT DEFAULT 'trending_movies',
    hero_carousel_custom_movie_list_id TEXT,
    hero_carousel_custom_show_list_id TEXT,
    hero_carousel_mdblist_movie_id TEXT,
    hero_carousel_mdblist_show_id TEXT,
    is_kids_profile BOOLEAN DEFAULT FALSE,
    parent_passcode TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON user_settings FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON user_settings FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 3. Custom Lists
CREATE TABLE IF NOT EXISTS custom_lists (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    list_id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    icon_name TEXT,
    display_style TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, list_id)
);
CREATE INDEX IF NOT EXISTS idx_custom_lists_user ON custom_lists(user_id);

ALTER TABLE custom_lists ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON custom_lists FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON custom_lists FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS custom_list_items (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    list_id TEXT NOT NULL,
    media_id INTEGER NOT NULL,
    media_type TEXT NOT NULL,
    title TEXT NOT NULL,
    poster_path TEXT,
    backdrop_path TEXT,
    year TEXT,
    vote_average DOUBLE PRECISION,
    overview TEXT,
    sort_order INTEGER DEFAULT 0,
    added_at TIMESTAMPTZ,
    UNIQUE(user_id, list_id, media_id, media_type)
);
CREATE INDEX IF NOT EXISTS idx_custom_list_items_user ON custom_list_items(user_id);
CREATE INDEX IF NOT EXISTS idx_custom_list_items_list ON custom_list_items(user_id, list_id);

ALTER TABLE custom_list_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON custom_list_items FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON custom_list_items FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 4. Browse Rows Config
CREATE TABLE IF NOT EXISTS browse_config (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    row_id TEXT NOT NULL,
    row_type TEXT NOT NULL,
    title TEXT NOT NULL,
    is_enabled BOOLEAN DEFAULT TRUE,
    sort_order INTEGER DEFAULT 0,
    UNIQUE(user_id, row_id)
);
CREATE INDEX IF NOT EXISTS idx_browse_config_user ON browse_config(user_id);

ALTER TABLE browse_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON browse_config FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON browse_config FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 5. Extension Lists
CREATE TABLE IF NOT EXISTS extension_lists (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    list_id TEXT NOT NULL,
    name TEXT NOT NULL,
    source TEXT NOT NULL,
    custom_name TEXT,
    show_on_home BOOLEAN DEFAULT FALSE,
    last_synced TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, list_id)
);
CREATE INDEX IF NOT EXISTS idx_extension_lists_user ON extension_lists(user_id);

ALTER TABLE extension_lists ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON extension_lists FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON extension_lists FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS extension_list_items (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    list_id TEXT NOT NULL,
    media_id INTEGER NOT NULL,
    media_type TEXT NOT NULL,
    title TEXT NOT NULL,
    poster_path TEXT,
    backdrop_path TEXT,
    year TEXT,
    vote_average DOUBLE PRECISION,
    overview TEXT,
    sort_order INTEGER DEFAULT 0,
    UNIQUE(user_id, list_id, media_id, media_type)
);
CREATE INDEX IF NOT EXISTS idx_extension_list_items_user ON extension_list_items(user_id);
CREATE INDEX IF NOT EXISTS idx_extension_list_items_list ON extension_list_items(user_id, list_id);

ALTER TABLE extension_list_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON extension_list_items FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON extension_list_items FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 6. Custom Home Rows
CREATE TABLE IF NOT EXISTS custom_home_rows (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    row_id TEXT NOT NULL,
    name TEXT NOT NULL,
    row_type TEXT NOT NULL,
    imported_list_id TEXT,
    hub_image_url TEXT,
    is_enabled BOOLEAN DEFAULT TRUE,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, row_id)
);
CREATE INDEX IF NOT EXISTS idx_custom_home_rows_user ON custom_home_rows(user_id);

ALTER TABLE custom_home_rows ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON custom_home_rows FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON custom_home_rows FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 7. Network Hubs Config
CREATE TABLE IF NOT EXISTS network_hubs_config (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    hub_id TEXT NOT NULL,
    is_enabled BOOLEAN DEFAULT TRUE,
    sort_order INTEGER DEFAULT 0,
    UNIQUE(user_id, hub_id)
);
CREATE INDEX IF NOT EXISTS idx_network_hubs_config_user ON network_hubs_config(user_id);

ALTER TABLE network_hubs_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON network_hubs_config FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON network_hubs_config FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 8. Custom JSON Hubs
CREATE TABLE IF NOT EXISTS custom_json_hubs (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    hub_id TEXT NOT NULL,
    name TEXT NOT NULL,
    json_url TEXT NOT NULL,
    icon_url TEXT,
    image_url TEXT,
    brand_color TEXT,
    is_enabled BOOLEAN DEFAULT TRUE,
    sort_order INTEGER DEFAULT 0,
    last_synced TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    source TEXT,
    mdblist_id TEXT,
    mdblist_ids JSONB,
    row_name TEXT,
    UNIQUE(user_id, hub_id)
);
CREATE INDEX IF NOT EXISTS idx_custom_json_hubs_user ON custom_json_hubs(user_id);

ALTER TABLE custom_json_hubs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON custom_json_hubs FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON custom_json_hubs FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 9. Hidden Sections
CREATE TABLE IF NOT EXISTS hidden_sections (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE,
    hide_studios_row BOOLEAN DEFAULT FALSE,
    hide_networks_row BOOLEAN DEFAULT FALSE,
    hide_for_you_row BOOLEAN DEFAULT FALSE,
    hide_discover_section BOOLEAN DEFAULT FALSE
);
ALTER TABLE hidden_sections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON hidden_sections FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON hidden_sections FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 10. Browse Sections Order
CREATE TABLE IF NOT EXISTS browse_sections (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    section_id TEXT NOT NULL,
    section_type TEXT NOT NULL,
    is_enabled BOOLEAN DEFAULT TRUE,
    sort_order INTEGER DEFAULT 0,
    UNIQUE(user_id, section_id)
);
CREATE INDEX IF NOT EXISTS idx_browse_sections_user ON browse_sections(user_id);

ALTER TABLE browse_sections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON browse_sections FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON browse_sections FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 11. Profiles
CREATE TABLE IF NOT EXISTS profiles (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    profile_id TEXT NOT NULL,
    name TEXT NOT NULL,
    avatar TEXT NOT NULL,
    color TEXT NOT NULL,
    age_group TEXT NOT NULL,
    is_kids BOOLEAN DEFAULT FALSE,
    date_of_birth TEXT,
    hero_carousel_width_ratio DOUBLE PRECISION,
    hero_carousel_aspect TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, profile_id)
);
CREATE INDEX IF NOT EXISTS idx_profiles_user ON profiles(user_id);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON profiles FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON profiles FOR ALL TO authenticated USING (true) WITH CHECK (true);
```

## How to Set Up

1. Go to your Supabase Dashboard
2. Navigate to **SQL Editor** → **New Query**
3. Paste the SQL above
4. Click **Run**
5. Verify the table was created in **Table Editor**

## Row Level Security Notes

The current setup allows all devices to read/write their own data using a unique device ID stored locally. This is suitable for personal use.

For production apps with user accounts, you would:
1. Enable Supabase Auth
2. Replace `device_id` with `user_id` 
3. Update RLS policies to use `auth.uid()`

## Testing

After setup, go to **Settings** in the app and:
1. Enable **Cloud Sync**
2. Add some items to your watchlist
3. Use **Sync Options** → **Upload to Cloud**
4. Check the Supabase Table Editor to see your data

---

## Social Features Migration

Run this SQL in **SQL Editor** → **New Query** to add social features (5 new tables + 1 helper function).

```sql
-- ===================================================
-- WatchGuide Social Features — Migration
-- ===================================================

-- 12. Social Profiles
CREATE TABLE IF NOT EXISTS social_profiles (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    username TEXT UNIQUE,
    avatar_url TEXT,
    bio TEXT,
    is_public BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_social_profiles_user ON social_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_social_profiles_username ON social_profiles(username);
ALTER TABLE social_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON social_profiles FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON social_profiles FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 13. Follows
CREATE TABLE IF NOT EXISTS follows (
    id SERIAL PRIMARY KEY,
    follower_id TEXT NOT NULL,
    following_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(follower_id, following_id),
    CHECK (follower_id != following_id)
);
CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id);
ALTER TABLE follows ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON follows FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON follows FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 14. Watch Activity (Friends Feed)
CREATE TABLE IF NOT EXISTS watch_activity (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    activity_type TEXT NOT NULL CHECK (activity_type IN (
        'watched', 'rated', 'added_watchlist', 'liked', 'started_watching'
    )),
    media_id INTEGER NOT NULL,
    media_type TEXT NOT NULL CHECK (media_type IN ('movie', 'tv')),
    title TEXT NOT NULL,
    poster_path TEXT,
    rating REAL,
    comment TEXT,
    season_number INTEGER,
    episode_number INTEGER,
    is_public BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_watch_activity_user ON watch_activity(user_id);
CREATE INDEX IF NOT EXISTS idx_watch_activity_user_time ON watch_activity(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_watch_activity_media ON watch_activity(media_id, media_type);
CREATE INDEX IF NOT EXISTS idx_watch_activity_created ON watch_activity(created_at DESC);
ALTER TABLE watch_activity ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON watch_activity FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON watch_activity FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 15. Watch Parties
CREATE TABLE IF NOT EXISTS watch_parties (
    id SERIAL PRIMARY KEY,
    party_id TEXT NOT NULL UNIQUE,
    host_user_id TEXT NOT NULL,
    title TEXT NOT NULL,
    media_id INTEGER NOT NULL,
    media_type TEXT NOT NULL CHECK (media_type IN ('movie', 'tv')),
    media_title TEXT NOT NULL,
    poster_path TEXT,
    scheduled_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'active', 'completed', 'cancelled'
    )),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_watch_parties_host ON watch_parties(host_user_id);
CREATE INDEX IF NOT EXISTS idx_watch_parties_party_id ON watch_parties(party_id);
CREATE INDEX IF NOT EXISTS idx_watch_parties_status ON watch_parties(status);
ALTER TABLE watch_parties ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON watch_parties FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON watch_parties FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 16. Watch Party Members
CREATE TABLE IF NOT EXISTS watch_party_members (
    id SERIAL PRIMARY KEY,
    party_id TEXT NOT NULL REFERENCES watch_parties(party_id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    rsvp_status TEXT NOT NULL DEFAULT 'invited' CHECK (rsvp_status IN (
        'invited', 'accepted', 'declined', 'maybe'
    )),
    joined_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(party_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_watch_party_members_party ON watch_party_members(party_id);
CREATE INDEX IF NOT EXISTS idx_watch_party_members_user ON watch_party_members(user_id);
ALTER TABLE watch_party_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON watch_party_members FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON watch_party_members FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Helper: Activity Feed Function
CREATE OR REPLACE FUNCTION get_activity_feed(
    p_user_id TEXT,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    activity_id INTEGER,
    user_id TEXT,
    display_name TEXT,
    username TEXT,
    avatar_url TEXT,
    activity_type TEXT,
    media_id INTEGER,
    media_type TEXT,
    title TEXT,
    poster_path TEXT,
    rating REAL,
    comment TEXT,
    season_number INTEGER,
    episode_number INTEGER,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        wa.id AS activity_id,
        wa.user_id,
        sp.display_name,
        sp.username,
        sp.avatar_url,
        wa.activity_type,
        wa.media_id,
        wa.media_type,
        wa.title,
        wa.poster_path,
        wa.rating,
        wa.comment,
        wa.season_number,
        wa.episode_number,
        wa.created_at
    FROM watch_activity wa
    INNER JOIN follows f ON f.following_id = wa.user_id
    INNER JOIN social_profiles sp ON sp.user_id = wa.user_id
    WHERE f.follower_id = p_user_id
      AND wa.is_public = TRUE
    ORDER BY wa.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql;

-- Enable Realtime for social tables
ALTER PUBLICATION supabase_realtime ADD TABLE watch_activity;
ALTER PUBLICATION supabase_realtime ADD TABLE watch_parties;
ALTER PUBLICATION supabase_realtime ADD TABLE watch_party_members;
```

### After running the SQL above, verify:
1. **Table Editor** shows 5 new tables: `social_profiles`, `follows`, `watch_activity`, `watch_parties`, `watch_party_members`
2. **Database → Functions** shows `get_activity_feed`
3. **Database → Replication** shows the 3 tables enabled for Realtime

---

## Social Extension for iCloud-Only Users

Social features (activity feed, watch parties, follows) are powered exclusively by Supabase. **CloudKit is not used for social features.**

### How it works

| User Type | Data Sync | Social Features |
|---|---|---|
| **Supabase user** | Supabase | ✅ Available automatically |
| **iCloud-only user** | CloudKit (private) | ✅ Available after connecting Supabase as a "Social Extension" |
| **No account** | Local only | ❌ Not available |

### For iCloud-only users

Users who sync via CloudKit can optionally connect to Supabase **just for social features**. Their data sync remains on CloudKit — only the social tables (`social_profiles`, `follows`, `watch_activity`, `watch_parties`, `watch_party_members`) are used on Supabase.

The app will show a "Connect Social" option in Settings that:
1. Creates a Supabase social-only account using their iCloud user ID as the identifier
2. Enables the activity feed, follow system, and watch parties
3. Does **not** migrate any data sync — lists, settings, and watchlist remain on CloudKit

This means all social interactions happen on one unified platform (Supabase) regardless of the user's sync provider.

---

## Social Feed Migration (Posts, Replies, Likes, DMs)

Run this SQL in **SQL Editor** → **New Query** to add the social feed tables and RPC functions. This must be run **after** the Social Features Migration above (since it references `social_profiles`).

```sql
-- ===================================================
-- WatchGuide Social Feed — Migration
-- ===================================================

-- 17. Social Posts
CREATE TABLE IF NOT EXISTS social_posts (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    body TEXT NOT NULL,
    segments JSONB,
    media_intent TEXT CHECK (media_intent IN (
        'want_to_watch', 'going_to_watch', 'currently_watching'
    )),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_social_posts_user ON social_posts(user_id);
CREATE INDEX IF NOT EXISTS idx_social_posts_created ON social_posts(created_at DESC);
ALTER TABLE social_posts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON social_posts FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON social_posts FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 18. Social Replies
CREATE TABLE IF NOT EXISTS social_replies (
    id TEXT PRIMARY KEY,
    post_id TEXT NOT NULL REFERENCES social_posts(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    body TEXT NOT NULL,
    segments JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_social_replies_post ON social_replies(post_id);
CREATE INDEX IF NOT EXISTS idx_social_replies_created ON social_replies(created_at ASC);
ALTER TABLE social_replies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON social_replies FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON social_replies FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 19. Social Post Likes
CREATE TABLE IF NOT EXISTS social_post_likes (
    post_id TEXT NOT NULL REFERENCES social_posts(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_social_post_likes_user ON social_post_likes(user_id);
ALTER TABLE social_post_likes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON social_post_likes FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON social_post_likes FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 20. Social Direct Messages
CREATE TABLE IF NOT EXISTS social_dms (
    id TEXT PRIMARY KEY,
    from_user_id TEXT NOT NULL,
    to_user_id TEXT NOT NULL,
    body TEXT NOT NULL,
    watch_party_id TEXT,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_social_dms_from ON social_dms(from_user_id);
CREATE INDEX IF NOT EXISTS idx_social_dms_to ON social_dms(to_user_id);
CREATE INDEX IF NOT EXISTS idx_social_dms_created ON social_dms(created_at DESC);
ALTER TABLE social_dms ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations for anon" ON social_dms FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations for authenticated" ON social_dms FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ===================================================
-- RPC Functions
-- ===================================================

-- get_social_feed: Returns posts from people the user follows + their own posts,
-- with author profile info, reply count, like count, and whether the user liked it.
CREATE OR REPLACE FUNCTION get_social_feed(
    p_user_id TEXT,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    id TEXT,
    user_id TEXT,
    display_name TEXT,
    username TEXT,
    avatar_url TEXT,
    body TEXT,
    segments JSONB,
    media_intent TEXT,
    created_at TIMESTAMPTZ,
    reply_count INTEGER,
    like_count INTEGER,
    liked_by_me BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        sp.id,
        sp.user_id,
        prof.display_name,
        prof.username,
        prof.avatar_url,
        sp.body,
        sp.segments,
        sp.media_intent,
        sp.created_at,
        COALESCE((SELECT COUNT(*)::INTEGER FROM social_replies sr WHERE sr.post_id = sp.id), 0) AS reply_count,
        COALESCE((SELECT COUNT(*)::INTEGER FROM social_post_likes spl WHERE spl.post_id = sp.id), 0) AS like_count,
        EXISTS(SELECT 1 FROM social_post_likes spl2 WHERE spl2.post_id = sp.id AND spl2.user_id = p_user_id) AS liked_by_me
    FROM social_posts sp
    INNER JOIN social_profiles prof ON prof.user_id = sp.user_id
    WHERE sp.user_id = p_user_id
       OR sp.user_id IN (SELECT f.following_id FROM follows f WHERE f.follower_id = p_user_id)
    ORDER BY sp.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql;

-- get_post_replies: Returns replies for a given post with author profile info.
CREATE OR REPLACE FUNCTION get_post_replies(
    p_post_id TEXT,
    p_user_id TEXT
)
RETURNS TABLE (
    id TEXT,
    post_id TEXT,
    user_id TEXT,
    display_name TEXT,
    username TEXT,
    avatar_url TEXT,
    body TEXT,
    segments JSONB,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        sr.id,
        sr.post_id,
        sr.user_id,
        prof.display_name,
        prof.username,
        prof.avatar_url,
        sr.body,
        sr.segments,
        sr.created_at
    FROM social_replies sr
    INNER JOIN social_profiles prof ON prof.user_id = sr.user_id
    WHERE sr.post_id = p_post_id
    ORDER BY sr.created_at ASC;
END;
$$ LANGUAGE plpgsql;

-- toggle_post_like: Inserts or removes a like. Returns {"liked": true/false}.
CREATE OR REPLACE FUNCTION toggle_post_like(
    p_post_id TEXT,
    p_user_id TEXT
)
RETURNS JSON AS $$
DECLARE
    already_liked BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM social_post_likes
        WHERE post_id = p_post_id AND user_id = p_user_id
    ) INTO already_liked;

    IF already_liked THEN
        DELETE FROM social_post_likes
        WHERE post_id = p_post_id AND user_id = p_user_id;
        RETURN json_build_object('liked', false);
    ELSE
        INSERT INTO social_post_likes (post_id, user_id)
        VALUES (p_post_id, p_user_id);
        RETURN json_build_object('liked', true);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Enable Realtime for social feed tables (safe to re-run)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'social_posts') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE social_posts;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'social_replies') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE social_replies;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'social_dms') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE social_dms;
    END IF;
END $$;
```

### After running the SQL above, verify:
1. **Table Editor** shows 4 new tables: `social_posts`, `social_replies`, `social_post_likes`, `social_dms`
2. **Database → Functions** shows 3 new functions: `get_social_feed`, `get_post_replies`, `toggle_post_like`
3. **Database → Replication** shows the 3 tables enabled for Realtime

### Table → Model mapping

| Supabase Table | Swift Model | Service Method |
|---|---|---|
| `social_posts` | `SocialPost` | `createPost()`, `getSocialFeed()` |
| `social_replies` | `SocialReply` | `replyToPost()`, `getReplies()` |
| `social_post_likes` | _(internal)_ | `togglePostLike()` |
| `social_dms` | `SocialDM` | `sendDirectMessage()`, `getDirectMessages()` |

### How data flows

1. **Creating a post:** The app calls `SocialService.createPost()` which INSERTs into `social_posts`. The `segments` column stores a JSONB array of `PostSegment` objects (text, mentions, media tags).
2. **Reading the feed:** `getSocialFeed()` calls the `get_social_feed` RPC, which JOINs `social_posts` with `social_profiles` and counts replies/likes from the related tables. Returns posts from people the user follows + their own posts.
3. **Liking a post:** `togglePostLike()` calls the `toggle_post_like` RPC, which inserts or deletes from `social_post_likes` and returns `{"liked": true/false}`.
4. **Replying:** `replyToPost()` INSERTs into `social_replies`. Replies are fetched via the `get_post_replies` RPC which JOINs with `social_profiles` for author info.
5. **DMs / Watch Party invites:** `sendDirectMessage()` INSERTs into `social_dms` with an optional `watch_party_id` linking to an existing watch party.

### Segments JSONB format

The `segments` column in `social_posts` and `social_replies` stores an array of tagged objects:

```json
[
  {"kind": "text", "text": "Would you like to watch "},
  {"kind": "mention", "username": "jason", "userId": "abc-123"},
  {"kind": "text", "text": " "},
  {"kind": "mediaTag", "title": "Superman", "mediaId": 209867, "mediaType": "movie", "posterPath": "/path.jpg"}
]
```

This allows the app to render rich text with tappable @mentions and clickable movie/show tags.

---

## API Response Cache Migration

Run this SQL in **SQL Editor** → **New Query** to add the shared server-side API response cache. This table stores responses from all external APIs (TMDB, MDBList, FanArt, TheTVDB, OMDb, StreamingDeepLink) so that all users share a common cache, reducing API load and improving performance.

```sql
-- ===================================================
-- WatchGuide API Response Cache — Migration
-- ===================================================

-- 21. Shared API Response Cache
-- All users read/write to the same cache. No user_id column.
CREATE TABLE IF NOT EXISTS api_cache (
    cache_key TEXT PRIMARY KEY,
    source TEXT NOT NULL,
    response_data JSONB NOT NULL,
    ttl_seconds INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    hit_count INTEGER NOT NULL DEFAULT 0
);

-- Index for cleanup queries (expired entries)
CREATE INDEX IF NOT EXISTS idx_api_cache_expires_at ON api_cache(expires_at);

-- Index for source-based filtering/monitoring
CREATE INDEX IF NOT EXISTS idx_api_cache_source ON api_cache(source);

-- Index for LRU-style cleanup (least recently created + expired)
CREATE INDEX IF NOT EXISTS idx_api_cache_created ON api_cache(created_at);

-- RLS: shared cache, all roles can read/write
ALTER TABLE api_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow read for anon" ON api_cache FOR SELECT TO anon USING (true);
CREATE POLICY "Allow insert for anon" ON api_cache FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "Allow update for anon" ON api_cache FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow read for authenticated" ON api_cache FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow insert for authenticated" ON api_cache FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Allow update for authenticated" ON api_cache FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- Scheduled cleanup function: delete expired entries
CREATE OR REPLACE FUNCTION cleanup_expired_cache()
RETURNS void AS $$
BEGIN
    DELETE FROM api_cache WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- Optional: schedule automatic cleanup every hour via pg_cron
-- (Requires pg_cron extension enabled in Supabase dashboard)
-- SELECT cron.schedule('cleanup-api-cache', '0 * * * *', 'SELECT cleanup_expired_cache()');
```

### After running the SQL above, verify:
1. **Table Editor** shows the `api_cache` table with columns: `cache_key`, `source`, `response_data`, `ttl_seconds`, `created_at`, `expires_at`, `hit_count`
2. **Database → Functions** shows `cleanup_expired_cache`
3. Run `SELECT cleanup_expired_cache();` to verify the function works

### Cache TTL Summary

| Data Type | TTL | Source |
|-----------|-----|--------|
| Trending/Popular/Search/Discover | 1 hour | TMDB |
| Movie/TV Details, Credits, Videos, Providers | 24 hours | TMDB |
| Genres | 30 days | TMDB |
| Artwork (images) | 7 days | TMDB, FanArt |
| Ratings | 12 hours | MDBList, OMDb |
| List items | 1 hour | MDBList |
| Episode images | 7 days | TheTVDB |
| Deep links | 24 hours | StreamingDeepLink (warmed daily on app launch) |

### Cache Sources

| Source Value | Service | Description |
|-------------|---------|-------------|
| `tmdb` | TMDBService | The Movie Database API responses |
| `mdblist` | MDBListService | MDBList ratings and list items |
| `fanart` | FanArtService | FanArt.tv artwork responses |
| `thetvdb` | TheTVDBService | TheTVDB episode image responses |
| `omdb` | OMDbService | OMDb ratings responses |
| `deeplink` | StreamingDeepLinkService | Movie of the Night deep link responses |
