import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { useLanguageState } from '@/lib/language';
import { fetchProductLabels, saveProductLabel, type ProductLabel } from '@/lib/platform-institutions';
import { Row } from '@/ui/admin/parts';
import { BottomSheet, Button, ErrorState, Skeleton, TextField, useSnackbar } from '@/ui/components';
import { usePanel } from '@/ui/panel/PanelContext';
import { PanelShell } from '@/ui/panel/PanelShell';

// Product-default words (0B.04-T10): the neutral words under every industry pack (used when a pack has no word for a
// key). Changing them never touches an institution's own words; industry and type words are edited in the pack /
// profile versions.
export default function PanelProductLabels() {
  const { t } = useTranslation('panel');
  const { language } = useLanguageState();
  const { state } = usePanel();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [rows, setRows] = useState<ProductLabel[] | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [editing, setEditing] = useState<ProductLabel | null>(null);
  const [form, setForm] = useState({ en_singular: '', en_plural: '', bn: '' });
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    const r = await fetchProductLabels();
    if (r.error) setError(r.error);
    else setRows(r.data ?? []);
  }, []);
  useEffect(() => {
    if (state.status === 'ready') void load();
  }, [state.status, load]);

  const open = (l: ProductLabel) => {
    setEditing(l);
    setForm({ en_singular: l.en_singular ?? '', en_plural: l.en_plural ?? '', bn: l.bn_forms?.base ?? '' });
  };
  const save = async () => {
    if (!editing) return;
    setBusy(true);
    const r = await saveProductLabel(editing.key, form.en_singular, form.en_plural, form.bn);
    setBusy(false);
    if (r.error) return snackbar.show({ text: errorText(r.error).message });
    snackbar.show({ text: t('productLabels.saved') });
    setEditing(null);
    void load();
  };

  return (
    <PanelShell permission="platform.profiles" title={t('productLabels.title')} testID="panel-product-labels">
      <AppText>{t('productLabels.intro')}</AppText>
      {error ? <ErrorState error={error} onRetry={() => void load()} /> : !rows ? <Skeleton lines={8} /> : (
        <View style={{ gap: 8 }}>
          {rows.map((l) => (
            <Row key={l.key} icon="translate" title={`${l.key} → ${(language === 'bn' ? l.bn_forms?.base : l.en_singular) ?? '—'}`}
              testID={`product-label-${l.key}`} onPress={() => open(l)} />
          ))}
        </View>
      )}
      {editing ? (
        <BottomSheet visible onClose={() => setEditing(null)} title={editing.key} testID="product-label-sheet"
          footer={<Button label={t('productLabels.save')} loading={busy} fullWidth onPress={() => void save()} testID="product-label-save" />}>
          <TextField label={t('productLabels.enSingular')} value={form.en_singular} onChangeText={(v) => setForm((f) => ({ ...f, en_singular: v }))}
            maxLength={editing.max_length} testID="product-label-en" />
          <TextField label={t('productLabels.enPlural')} value={form.en_plural} onChangeText={(v) => setForm((f) => ({ ...f, en_plural: v }))}
            maxLength={editing.max_length} testID="product-label-en-plural" />
          <TextField label={t('productLabels.bn')} value={form.bn} onChangeText={(v) => setForm((f) => ({ ...f, bn: v }))}
            maxLength={editing.max_length} testID="product-label-bn" />
        </BottomSheet>
      ) : null}
    </PanelShell>
  );
}
