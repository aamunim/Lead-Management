import { callWithSessionRetry, type ErrorInfo } from './errors';
import type { Text } from './packs';
import { supabase } from './supabase';

// Custom fields (0B.06): definitions per entity and the values API. The server validates every value, keeps sensitive
// ones from people without custom_field.view_sensitive and enforces the plan limit on field count.
export const FIELD_ENTITIES = ['lead', 'client', 'network'] as const;
export type FieldEntity = (typeof FIELD_ENTITIES)[number];
export const FIELD_TYPES = ['text', 'long_text', 'number', 'date', 'select', 'multi_select', 'phone', 'email', 'url', 'yes_no', 'gpa', 'file'] as const;
export type FieldType = (typeof FIELD_TYPES)[number];
export type Choice = { key: string; label: Text };
export type FieldDef = {
  id: string; entity: FieldEntity; key: string; label: Text; type: FieldType;
  options: { choices?: Choice[]; min?: number; max?: number; decimals?: number; max_length?: number };
  required: boolean; show_on_card: boolean; show_in_list: boolean; filterable: boolean; searchable: boolean; include_in_export: boolean;
  show_on_public_form: boolean; sort: number; group_label: Text | null; sensitive: boolean; created_from_preset: string | null;
  status: 'active' | 'retired'; values: number;
};
export const FLAGS = ['required', 'show_on_card', 'show_in_list', 'filterable', 'searchable', 'include_in_export', 'show_on_public_form', 'sensitive'] as const;
type Result<T> = { data: T | null; error: ErrorInfo | null };

const rpc = <T>(where: string, fn: string, args?: Record<string, unknown>): Promise<Result<T>> =>
  callWithSessionRetry<T>(where, async () => {
    const { data, error } = await supabase.rpc(fn, args);
    return { data: data as T | null, error };
  });

export const fetchFields = (entity: FieldEntity) =>
  rpc<{ fields: FieldDef[]; limit: { used: number; limit: number | null; level: string } }>('fields.list', 'custom_fields_list', { p_entity: entity });
export const saveField = (entity: FieldEntity, id: string | null, field: Partial<FieldDef>) =>
  rpc<{ id: string }>('fields.save', 'custom_field_save', { p_entity: entity, p_id: id, p_field: field });
export const reorderFields = (entity: FieldEntity, order: { id: string; group_label: Text | null }[]) =>
  rpc<null>('fields.reorder', 'custom_fields_reorder', { p_entity: entity, p_order: order });
export const retireField = (id: string, retired: boolean) => rpc<null>('fields.retire', 'custom_field_retire', { p_id: id, p_retired: retired });

/** "key | English | বাংলা" per line ↔ choices (the builder's simple editor for select options). */
export function choicesFromText(text: string): Choice[] {
  return text.split('\n').map((l) => l.split('|').map((p) => p.trim())).filter((p) => p[0])
    .map(([key, en, bn]) => ({ key: key.toLowerCase().replace(/[^a-z0-9_]+/g, '_'), label: { en: en || key, bn: bn || en || key } }));
}
export const choicesToText = (choices: Choice[] = []) => choices.map((c) => `${c.key} | ${c.label.en} | ${c.label.bn}`).join('\n');

/** A field key from its English name: "Father's phone" → "fathers_phone". */
export const keyFromName = (name: string) => name.toLowerCase().replace(/['’]/g, '').replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').replace(/^(\d)/, 'f_$1').slice(0, 60);
