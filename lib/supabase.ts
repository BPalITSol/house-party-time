import {createClient} from "@supabase/supabase-js";

const url=process.env.NEXT_PUBLIC_SUPABASE_URL?.trim()??"";
const anonKey=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim()??"";
const placeholder=/YOUR_|placeholder|example/i;

export const supabaseConfigurationError=!url||!anonKey||placeholder.test(url)||placeholder.test(anonKey)
  ?"Supabase is not configured. Add your project URL and anon key to .env.local, then restart the app."
  :null;

// A syntactically valid fallback keeps the UI renderable when local configuration
// is absent. Callers check supabaseConfigurationError before making requests.
export const supabase=createClient(
  supabaseConfigurationError?"http://localhost:54321":url,
  supabaseConfigurationError?"missing-supabase-anon-key":anonKey,
);
