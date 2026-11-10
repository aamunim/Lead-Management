#!/usr/bin/env bash
# Web build connected to the LOCAL Supabase (for UI tests). Reads the local URL and public key from `supabase status`;
# nothing is written to disk except dist/.
set -euo pipefail
status="$(npx --yes supabase@3.1.0 status -o json 2>/dev/null)"
url="$(node -e 'const s=JSON.parse(process.argv[1]); process.stdout.write(s.API_URL)' "$status")"
key="$(node -e 'const s=JSON.parse(process.argv[1]); process.stdout.write(s.PUBLISHABLE_KEY ?? s.ANON_KEY)' "$status")"
EXPO_PUBLIC_SUPABASE_URL="$url" EXPO_PUBLIC_SUPABASE_KEY="$key" npx expo export --platform web --clear
