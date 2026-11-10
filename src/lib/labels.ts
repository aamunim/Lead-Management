import { useSyncExternalStore } from 'react';

import i18n from '@/i18n';
import type { Language } from '@/i18n/language';
import { bundledLabels } from '@/i18n/resources';

import { currentClaims } from './session';
import { onSettingsVersion } from './settings-version';
import { supabase } from './supabase';

// Label dictionary on the client (0A.12-T3/T4). The institution's words (labels_get) are loaded into the i18next
// `labels` namespace, so translations use them as $t(labels:client.plural) and every screen re-renders when they
// change. Before sign-in, offline, or after sign-out the bundled education defaults are used.

export type BnForms = { base: string; plural: string; possessive: string; objective: string; plural_oblique: string };
export type LabelValue = { en_singular: string; en_plural: string; bn_forms: BnForms };
export type LabelEntry = {
  group: string;
  animate: boolean;
  max_length: number;
  lockable: boolean;
  legacy_key: string | null;
  resolved: LabelValue & { source: string; locked: boolean };
  default: LabelValue | null;
  product: LabelValue | null;
};
export type LabelForm = 'singular' | 'plural' | 'possessive' | 'objective' | 'plural_oblique';

type State = { entries: Record<string, LabelEntry> | null; institutionId: string | null; version: number };
let state: State = { entries: null, institutionId: null, version: 0 };
const subscribers = new Set<() => void>();

function publish(next: State) {
  state = next;
  for (const notify of subscribers) notify();
}

function nest(target: Record<string, unknown>, key: string, value: unknown) {
  const parts = key.split('.');
  let node = target;
  for (const part of parts.slice(0, -1)) node = (node[part] ??= {}) as Record<string, unknown>;
  node[parts[parts.length - 1]] = value;
}

/** Turns labels_get() entries into i18next trees: en {singular, plural}, bn {singular, plural, possessive, …}. */
export function toResources(entries: Record<string, LabelEntry>): Record<Language, Record<string, unknown>> {
  const en: Record<string, unknown> = {};
  const bn: Record<string, unknown> = {};
  for (const [key, entry] of Object.entries(entries)) {
    const r = entry.resolved;
    nest(en, key, { singular: r.en_singular, plural: r.en_plural });
    nest(bn, key, { singular: r.bn_forms.base, plural: r.bn_forms.plural, possessive: r.bn_forms.possessive,
      objective: r.bn_forms.objective, plural_oblique: r.bn_forms.plural_oblique });
  }
  return { en, bn };
}

function applyResources(trees: Record<Language, unknown>) {
  for (const lang of Object.keys(trees) as Language[]) {
    i18n.addResourceBundle(lang, 'labels', trees[lang], false, true); // replace, so removed renames disappear
  }
}

function useBundled() {
  applyResources(bundledLabels as unknown as Record<Language, unknown>);
  publish({ entries: null, institutionId: null, version: 0 });
}

/** Loads the active institution's labels; falls back to the bundled defaults when signed out. */
export async function loadLabels(): Promise<void> {
  const claims = await currentClaims();
  const institutionId = claims.active_institution_id ?? null;
  if (!claims.sub || !institutionId) {
    if (state.entries) useBundled();
    return;
  }
  const { data, error } = await supabase.rpc('labels_get');
  if (error || !data) return; // keep what is on screen; never blank the words on a failed call
  const result = data as { settings_version: number | null; labels: Record<string, LabelEntry> };
  applyResources(toResources(result.labels));
  publish({ entries: result.labels, institutionId, version: result.settings_version ?? 0 });
}

/** One word in the current language: label('client', 'plural') → "Students" / "শিক্ষার্থীরা". */
export function label(key: string, form: LabelForm = 'singular'): string {
  const lookup = i18n.t as unknown as (k: string, o?: object) => string; // label keys are data, checked by check:i18n
  return lookup(`labels:${key}.${form}`, { defaultValue: lookup(`labels:${key}.singular`) });
}

export function useLabelEntries(): State {
  return useSyncExternalStore(
    (notify) => {
      subscribers.add(notify);
      return () => subscribers.delete(notify);
    },
    () => state,
  );
}

// Sign-in / institution switch / token refresh → load; sign-out → bundled defaults; renamed words → reload.
supabase.auth.onAuthStateChange((event) => {
  if (event === 'SIGNED_OUT') useBundled();
  else if (event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED') setTimeout(() => void loadLabels().catch(() => undefined), 0);
});
onSettingsVersion((version) => {
  if (state.institutionId && version > state.version) void loadLabels().catch(() => undefined);
});
