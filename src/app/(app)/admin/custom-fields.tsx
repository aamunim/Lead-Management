import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import {
  FIELD_ENTITIES, FIELD_TYPES, FLAGS, choicesFromText, choicesToText, fetchFields, keyFromName, reorderFields, retireField, saveField,
  type FieldDef, type FieldEntity, type FieldType,
} from '@/lib/custom-fields';
import { label } from '@/lib/labels';
import { useLanguageState } from '@/lib/language';
import { pick, type Text } from '@/lib/packs';
import { Badge, CheckRow, Chips, Row, Section, SelectField, tDynamic } from '@/ui/admin/parts';
import { BottomSheet, Button, ErrorState, IconButton, Screen, Skeleton, TextField, useSnackbar } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Settings → Custom fields (0B.06-T7; Ch 14.6): one builder for leads, clients and the network. Fields are grouped and
// ordered (move up / down), added and changed in a sheet with every option and a preview of how the field looks on a
// form and on a card, and retired (their values are kept). Preset fields come from the institution's types. The
// number of active fields is a plan limit; sensitive fields are seen only by roles with the permission.
type Draft = {
  id: string | null; key: string; en: string; bn: string; type: FieldType; choices: string; min: string; max: string;
  flags: Record<(typeof FLAGS)[number], boolean>; groupEn: string; groupBn: string; hasValues: boolean; preset: string | null; status: string;
};
const emptyFlags = () => Object.fromEntries(FLAGS.map((f) => [f, f === 'include_in_export'])) as Draft['flags'];

export default function CustomFieldsScreen() {
  const { t } = useTranslation('admin');
  const { language } = useLanguageState();
  const { colors, space } = useTheme();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [entity, setEntity] = useState<FieldEntity>('lead');
  const [data, setData] = useState<Awaited<ReturnType<typeof fetchFields>>['data']>(null);
  const [error, setError] = useState<unknown>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    setData(null);
    const r = await fetchFields(entity);
    if (r.error) setError(r.error);
    else setData(r.data);
  }, [entity]);
  useEffect(() => {
    void load();
  }, [load]);

  const active = (data?.fields ?? []).filter((f) => f.status === 'active');
  const retired = (data?.fields ?? []).filter((f) => f.status === 'retired');
  const groups = Array.from(new Map(active.map((f) => [f.group_label ? pick(f.group_label, language) : '', f.group_label])).entries());

  const open = (f: FieldDef | null) => setDraft(f ? {
    id: f.id, key: f.key, en: f.label.en, bn: f.label.bn, type: f.type, choices: choicesToText(f.options.choices),
    min: f.options.min?.toString() ?? '', max: f.options.max?.toString() ?? '',
    flags: Object.fromEntries(FLAGS.map((k) => [k, f[k]])) as Draft['flags'],
    groupEn: f.group_label?.en ?? '', groupBn: f.group_label?.bn ?? '', hasValues: f.values > 0, preset: f.created_from_preset, status: f.status,
  } : { id: null, key: '', en: '', bn: '', type: 'text', choices: '', min: '', max: '', flags: emptyFlags(), groupEn: '', groupBn: '', hasValues: false,
    preset: null, status: 'active' });

  const move = async (index: number, delta: number) => {
    const order = [...active];
    const [f] = order.splice(index, 1);
    order.splice(index + delta, 0, f);
    const r = await reorderFields(entity, order.map((x) => ({ id: x.id, group_label: x.group_label })));
    if (r.error) snackbar.show({ text: errorText(r.error).message });
    void load();
  };
  const save = async () => {
    if (!draft) return;
    setBusy(true);
    const options: FieldDef['options'] = {};
    if (draft.type === 'select' || draft.type === 'multi_select') options.choices = choicesFromText(draft.choices);
    if (draft.type === 'number' && draft.min) options.min = Number(draft.min);
    if (draft.type === 'number' && draft.max) options.max = Number(draft.max);
    const group: Text | null = draft.groupEn.trim() ? { en: draft.groupEn.trim(), bn: draft.groupBn.trim() || draft.groupEn.trim() } : null;
    const r = await saveField(entity, draft.id, { key: draft.key || keyFromName(draft.en), label: { en: draft.en.trim(), bn: draft.bn.trim() },
      type: draft.type, options, group_label: group, ...draft.flags });
    setBusy(false);
    if (r.error) return snackbar.show({ text: errorText(r.error).message });
    snackbar.show({ text: t('fields.saved') });
    setDraft(null);
    void load();
  };
  const retire = async (id: string, value: boolean) => {
    const r = await retireField(id, value);
    snackbar.show({ text: r.error ? errorText(r.error).message : value ? t('fields.retired') : t('fields.restored') });
    setDraft(null);
    void load();
  };

  const typeChoices = FIELD_TYPES.map((v) => ({ value: v, label: tDynamic(`admin:fields.types.${v}`), testID: `field-type-${v}` }));
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('fields.title')} intro={t('fields.intro')} testID="custom-fields">
        <Chips label={t('fields.entity')} selected={entity} onSelect={setEntity}
          choices={FIELD_ENTITIES.map((e) => ({ value: e, label: label(e, 'plural'), testID: `fields-entity-${e}` }))} />
        {error ? <ErrorState error={error} onRetry={() => void load()} testID="fields-error" /> : !data ? <Skeleton lines={6} testID="fields-loading" /> : (
          <>
            <AppText variant="caption" testID="fields-limit">
              {data.limit.limit === null ? t('fields.countNoLimit', { count: data.limit.used }) : t('fields.count', { used: data.limit.used, limit: data.limit.limit })}
            </AppText>
            <Button icon="add" label={t('fields.add')} onPress={() => open(null)} testID="fields-add" />
            {active.length === 0 ? <AppText testID="fields-empty">{t('fields.empty')}</AppText> : null}
            {groups.map(([name]) => (
              <Section key={name || '_'} title={name || t('fields.noGroup')} testID={`fields-group-${name || 'none'}`}>
                {active.map((f, i) => ((f.group_label ? pick(f.group_label, language) : '') !== name ? null : (
                  <Row key={f.id} icon={f.sensitive ? 'shield' : 'text-fields'} title={pick(f.label, language)} testID={`field-${f.key}`}
                    subtitle={[tDynamic(`admin:fields.types.${f.type}`), f.required ? t('fields.flags.required') : null,
                      f.filterable ? t('fields.flags.filterable') : null, f.sensitive ? t('fields.flags.sensitive') : null,
                      f.created_from_preset ? t('fields.preset') : null].filter(Boolean).join(' · ')}
                    onPress={() => open(f)}
                    badge={(
                      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                        <IconButton icon="arrow-upward" label={t('fields.moveUp')} disabled={i === 0}
                          onPress={() => void move(i, -1)} testID={`field-up-${f.key}`} />
                        <IconButton icon="arrow-downward" label={t('fields.moveDown')} disabled={i === active.length - 1}
                          onPress={() => void move(i, 1)} testID={`field-down-${f.key}`} />
                      </View>
                    )} />
                )))}
              </Section>
            ))}
            {retired.length ? (
              <Section title={t('fields.retiredTitle')} testID="fields-retired">
                {retired.map((f) => (
                  <Row key={f.id} icon="archive" title={pick(f.label, language)} subtitle={t('fields.retiredHelp', { count: f.values })}
                    testID={`field-retired-${f.key}`}
                    badge={<Button variant="text" label={t('fields.restore')} onPress={() => void retire(f.id, false)} testID={`field-restore-${f.key}`} />} />
                ))}
              </Section>
            ) : null}
          </>
        )}
      </Screen>
      {draft ? (
        <BottomSheet visible onClose={() => setDraft(null)} title={draft.id ? t('fields.edit') : t('fields.add')} testID="field-sheet"
          footer={<Button label={t('fields.save')} loading={busy} fullWidth disabled={!draft.en.trim() || !draft.bn.trim()} onPress={() => void save()}
            testID="field-save" />}>
          <TextField label={t('fields.nameEn')} required value={draft.en} maxLength={80} testID="field-en"
            onChangeText={(v) => setDraft((d) => d && { ...d, en: v, key: d.id ? d.key : keyFromName(v) })} />
          <TextField label={t('fields.nameBn')} required value={draft.bn} maxLength={80} onChangeText={(v) => setDraft((d) => d && { ...d, bn: v })} testID="field-bn" />
          <TextField label={t('fields.key')} value={draft.key} maxLength={60} editable={!draft.hasValues} help={t('fields.keyHelp')}
            onChangeText={(v) => setDraft((d) => d && { ...d, key: keyFromName(v) })} testID="field-key" />
          <SelectField label={t('fields.type')} value={draft.type} choices={typeChoices} help={draft.hasValues ? t('fields.typeLocked') : undefined}
            onChange={(v) => { if (!draft.hasValues) setDraft((d) => d && { ...d, type: v }); }} testID="field-type" />
          {draft.type === 'select' || draft.type === 'multi_select' ? (
            <TextField label={t('fields.choices')} kind="multiline" value={draft.choices} help={t('fields.choicesHelp')}
              onChangeText={(v) => setDraft((d) => d && { ...d, choices: v })} testID="field-choices" />
          ) : null}
          {draft.type === 'number' ? (
            <View style={{ flexDirection: 'row', gap: space.sm }}>
              <View style={{ flex: 1 }}><TextField label={t('fields.min')} kind="decimal" value={draft.min} onChangeText={(v) => setDraft((d) => d && { ...d, min: v })} testID="field-min" /></View>
              <View style={{ flex: 1 }}><TextField label={t('fields.max')} kind="decimal" value={draft.max} onChangeText={(v) => setDraft((d) => d && { ...d, max: v })} testID="field-max" /></View>
            </View>
          ) : null}
          {FLAGS.map((k) => (
            <CheckRow key={k} label={t(`fields.flags.${k}`)} help={t(`fields.flagHelp.${k}`)} checked={draft.flags[k]}
              onToggle={() => setDraft((d) => d && { ...d, flags: { ...d.flags, [k]: !d.flags[k] } })} testID={`field-flag-${k}`} />
          ))}
          <TextField label={t('fields.groupEn')} value={draft.groupEn} maxLength={60} onChangeText={(v) => setDraft((d) => d && { ...d, groupEn: v })} testID="field-group-en" />
          <TextField label={t('fields.groupBn')} value={draft.groupBn} maxLength={60} onChangeText={(v) => setDraft((d) => d && { ...d, groupBn: v })} testID="field-group-bn" />
          <Preview draft={draft} language={language} />
          {draft.id ? (
            <Button variant="danger" label={t('fields.retire')} onPress={() => void retire(draft.id ?? '', true)} testID="field-retire" />
          ) : null}
        </BottomSheet>
      ) : null}
    </View>
  );
}

/** How the field will look: on a form (label, required mark, the kind of input) and on a card (label: value). */
function Preview({ draft, language }: { draft: Draft; language: string }) {
  const { t } = useTranslation('admin');
  const { colors, radius, space } = useTheme();
  const name = (language === 'bn' ? draft.bn : draft.en) || t('fields.sampleName');
  const sample = tDynamic(`admin:fields.samples.${draft.type}`);
  const choices = choicesFromText(draft.choices);
  return (
    <View style={{ gap: space.sm, padding: space.md, borderRadius: radius.md, backgroundColor: colors.surfaceContainerLow }} testID="field-preview">
      <AppText variant="label">{t('fields.previewForm')}</AppText>
      <AppText>{draft.flags.required ? t('fields.requiredName', { name }) : name}</AppText>
      {(draft.type === 'select' || draft.type === 'multi_select') && choices.length ? (
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: space.xs }}>
          {choices.map((c) => <Badge key={c.key} label={language === 'bn' ? c.label.bn : c.label.en} />)}
        </View>
      ) : (
        <View style={{ minHeight: 44, justifyContent: 'center', paddingHorizontal: space.md, borderRadius: radius.sm, borderWidth: 1, borderColor: colors.outline }}>
          <AppText style={{ color: colors.onSurfaceVariant }}>{sample}</AppText>
        </View>
      )}
      {draft.flags.show_on_card ? (
        <>
          <AppText variant="label">{t('fields.previewCard')}</AppText>
          <AppText variant="caption" testID="field-preview-card">{t('fields.cardLine', { name, value: draft.flags.sensitive ? '•••' : sample })}</AppText>
        </>
      ) : null}
    </View>
  );
}
