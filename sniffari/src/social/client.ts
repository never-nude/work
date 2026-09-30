import { createClient, type SupabaseClient } from '@supabase/supabase-js';

/**
 * Supabase connection. URL + anon key come from sniffari/.env.local (never committed):
 *   VITE_SUPABASE_URL=https://xxxx.supabase.co
 *   VITE_SUPABASE_ANON_KEY=eyJ…
 * The anon key is safe in the app — the database's row-level security decides what anyone can see.
 * Without them, the social features simply don't appear.
 */
const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const supabase: SupabaseClient | null = url && key ? createClient(url, key, { auth: { persistSession: true, autoRefreshToken: true } }) : null;

export const socialEnabled = supabase !== null;
