import { label } from '@/lib/labels';
import type { ModuleState } from '@/lib/modules';
import { tDynamic } from '@/ui/admin/parts';

/** A module's shown name: from the label system when it has a label key (e.g. "Alumni"), else its translation. */
export function moduleName(m: Pick<ModuleState, 'key' | 'label_key'>): string {
  return m.label_key ? label(m.label_key, 'plural') : tDynamic(`admin:modules.names.${m.key}`);
}
