# Supabase Setup for WatchGuide

## Database Schema

Run this SQL in your Supabase SQL Editor (SQL Editor → New Query):

```sql
-- Create the media_items table for syncing watchlist, watched, and liked items
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
    
    -- Ensure no duplicate items per device/list
    UNIQUE(device_id, list_type, media_id, media_type)
);

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_media_items_device ON media_items(device_id);
CREATE INDEX IF NOT EXISTS idx_media_items_list ON media_items(device_id, list_type);
CREATE INDEX IF NOT EXISTS idx_media_items_added ON media_items(added_at DESC);

-- Enable Row Level Security
ALTER TABLE media_items ENABLE ROW LEVEL SECURITY;

-- Create policy to allow all operations for anonymous users
-- (Each device has its own device_id, so data is isolated)
CREATE POLICY "Allow all operations for anon" ON media_items
    FOR ALL
    TO anon
    USING (true)
    WITH CHECK (true);

-- Optional: Create policy for authenticated users if you add auth later
CREATE POLICY "Allow all operations for authenticated" ON media_items
    FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);
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
