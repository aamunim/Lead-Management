// Search that also matches default words (0A.12-T7, Ch 8.9 rule 5). Pure: unit-tested in Node.
// "student" finds the clients module even when the institution calls it "Trainees", because the default word
// (Students), the old key (module.students) and the neutral key (module.clients) are searched too, in both languages.

export type SearchableLabel = {
  key: string;
  legacy_key?: string | null;
  current: string[]; // words in force (both languages, all forms)
  fallback: string[]; // default and product words (both languages, all forms)
};

type Value = { en_singular: string; en_plural: string; bn_forms: Record<string, string> } | null | undefined;
const wordsOf = (v: Value) => (v ? [v.en_singular, v.en_plural, ...Object.values(v.bn_forms ?? {})] : []);

export function toSearchable(entries: Record<string, { legacy_key: string | null; resolved: Value; default: Value; product: Value }>): SearchableLabel[] {
  return Object.entries(entries).map(([key, e]) => ({
    key, legacy_key: e.legacy_key, current: wordsOf(e.resolved), fallback: [...wordsOf(e.default), ...wordsOf(e.product)],
  }));
}

const normalize = (text: string) => text.toLowerCase().normalize('NFC').replace(/[\s._\-/]+/g, ' ').trim();
/** English plural → singular for matching ("students" → "student", "batches" → "batch"); Bangla left as typed. */
const stem = (word: string) => word.replace(/(ches|shes|xes|ses)$/, (m) => m.slice(0, -2)).replace(/ies$/, 'y').replace(/s$/, '');

function matches(haystack: string[], query: string): boolean {
  const q = normalize(query);
  const qs = stem(q);
  return haystack.some((word) => {
    const w = normalize(word);
    return w.includes(q) || (qs.length >= 3 && (w.includes(qs) || stem(w).includes(qs)));
  });
}

/** Keys that match, best first: current word, then default / product word, then the key or the old key. */
export function searchLabels(query: string, labels: SearchableLabel[]): string[] {
  if (!normalize(query)) return labels.map((l) => l.key);
  const scored: [string, number][] = [];
  for (const label of labels) {
    const keys = [label.key, label.legacy_key ?? ''].filter(Boolean);
    const score = matches(label.current, query) ? 3 : matches(label.fallback, query) ? 2 : matches(keys, query) ? 1 : 0;
    if (score > 0) scored.push([label.key, score]);
  }
  return scored.sort((a, b) => b[1] - a[1]).map(([key]) => key);
}
