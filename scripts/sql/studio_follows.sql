-- ===================================================
-- WatchGuide Studio Follows — Migration
-- ===================================================

-- 15. Studio Follows
-- One row per studio the user has followed or unfollowed. Studios the user
-- never touched have no row; the device keeps its defaults for those.
CREATE TABLE IF NOT EXISTS studio_follows (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    -- The studio name, lowercased. Each device generates its own random hub
    -- ids, so the name is what identifies the same studio across devices.
    hub_key TEXT NOT NULL,
    name TEXT NOT NULL,
    logo_path TEXT,
    company_ids INTEGER[] NOT NULL DEFAULT '{}',
    network_ids INTEGER[] NOT NULL DEFAULT '{}',
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    -- The app upserts on this pair (?on_conflict=user_id,hub_key).
    UNIQUE(user_id, hub_key)
);
CREATE INDEX IF NOT EXISTS idx_studio_follows_user ON studio_follows(user_id);

CREATE OR REPLACE FUNCTION public.set_studio_follows_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_studio_follows_updated_at ON studio_follows;
CREATE TRIGGER trg_studio_follows_updated_at
    BEFORE UPDATE ON studio_follows
    FOR EACH ROW EXECUTE FUNCTION set_studio_follows_updated_at();

ALTER TABLE studio_follows ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all operations for anon" ON studio_follows;
CREATE POLICY "Allow all operations for anon" ON studio_follows FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Allow all operations for authenticated" ON studio_follows;
CREATE POLICY "Allow all operations for authenticated" ON studio_follows FOR ALL TO authenticated USING (true) WITH CHECK (true);
