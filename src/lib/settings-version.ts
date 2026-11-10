// Tiny event hub for the x-settings-version response header (0A.08). Kept separate to avoid an import cycle between
// the Supabase client (which sees every response) and the settings store (which uses the client).
type Listener = (version: number) => void;
const listeners = new Set<Listener>();

export function onSettingsVersion(listener: Listener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function reportSettingsVersion(header: string | null): void {
  const version = header ? Number(header) : NaN;
  if (Number.isFinite(version)) for (const listener of listeners) listener(version);
}
