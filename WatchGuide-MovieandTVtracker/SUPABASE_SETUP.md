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
