import { useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { useLanguageState } from '@/lib/language';
import { useFormat } from '@/lib/locale';
import {
  discardDraft, fetchPack, parsePayload, pick, publishVersion, saveDraft, validatePack,
  type PackDetail, type PackKind, type PackPayload, type PackVersion, type Text,
} from '@/lib/packs';
import { Badge, Row, Section } from '@/ui/admin/parts';
import { Button, ErrorState, Skeleton, TextField, useConfirm, useSnackbar } from '@/ui/components';
import { usePanel } from '@/ui/panel/PanelContext';
import { PanelShell } from '@/ui/panel/PanelShell';
import { useTheme } from '@/ui/theme';

// One pack or type profile (0B.03-T9): what the chosen version sets (structured view), its version history, and the
// editor for the next version — name in both languages as fields, everything else as JSON. Validate checks the
// schema and the references on the server; only a valid draft can be published; a published version never changes.
type Keyed = { key: string; name: Text };

export default function PanelProfile() {
  const { kind, key } = useLocalSearchParams<{ kind: PackKind; key: string }>();
  const { t } = useTranslation('panel');
  const { language } = useLanguageState();
  const format = useFormat();
  const { colors, space } = useTheme();
  const { state } = usePanel();
  const snackbar = useSnackbar();
  const confirm = useConfirm();
  const errorText = useErrorText();
  const [detail, setDetail] = useState<PackDetail | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [shown, setShown] = useState<number | null>(null);
  const [text, setText] = useState<string | null>(null); // the editor (null = closed)
  const [notes, setNotes] = useState('');
  const [problems, setProblems] = useState<string[] | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    const r = await fetchPack(kind, key);
    if (r.error) return setError(r.error);
    setDetail(r.data);
    setShown(r.data?.versions[0]?.version ?? null);
  }, [kind, key]);
  useEffect(() => {
    if (state.status === 'ready') void load();
  }, [state.status, load]);

  const version = detail?.versions.find((v) => v.version === shown) ?? null;
  const draft = detail?.versions.find((v) => v.status === 'draft') ?? null;
  const parsed = useMemo(() => (text === null ? null : parsePayload(text)), [text]);

  const openEditor = () => {
    const base = draft ?? detail?.versions.find((v) => v.status === 'published');
    setText(JSON.stringify(base?.payload ?? {}, null, 2));
    setNotes(draft?.notes ?? '');
    setProblems(null);
  };
  const setName = (lang: 'en' | 'bn', value: string) => {
    if (!parsed || !('value' in parsed)) return;
    const next: PackPayload = { ...parsed.value, name: { ...(parsed.value.name ?? { en: '', bn: '' }), [lang]: value } };
    setText(JSON.stringify(next, null, 2));
  };
  const validate = async () => {
    if (!parsed || !('value' in parsed)) return;
    setBusy(true);
    const r = await validatePack(kind, key, parsed.value);
    setBusy(false);
    if (r.error) return snackbar.show({ text: errorText(r.error).message });
    setProblems(r.data ?? []);
  };
  const save = async () => {
    if (!parsed || !('value' in parsed)) return;
    setBusy(true);
    const r = await saveDraft(kind, key, parsed.value, notes.trim() || null);
    setBusy(false);
    if (r.error) return snackbar.show({ text: errorText(r.error).message });
    snackbar.show({ text: t('profiles.draftSaved', { version: r.data }) });
    setText(null);
    void load();
  };
  const publish = async () => {
    if (!draft) return;
    setBusy(true);
    const check = await validatePack(kind, key, draft.payload);
    if (check.data?.length) {
      setBusy(false);
      setProblems(check.data);
      return snackbar.show({ text: errorText({ messageKey: 'errors.profile_invalid', action: 'fix_input' }).message });
    }
    const ok = await confirm({ title: t('profiles.publishTitle', { version: draft.version }), message: t('profiles.publishBody'),
      confirmLabel: t('profiles.publish') });
    if (!ok) return setBusy(false);
    const r = await publishVersion(kind, key, draft.version, draft.notes);
    setBusy(false);
    snackbar.show({ text: r.error ? errorText(r.error).message : t('profiles.publishedNow', { version: draft.version }) });
    setProblems(null);
    void load();
  };
  const discard = async () => {
    if (!(await confirm({ title: t('profiles.discardTitle'), message: t('profiles.discardBody'), confirmLabel: t('profiles.discard'), danger: true }))) return;
    const r = await discardDraft(kind, key);
    snackbar.show({ text: r.error ? errorText(r.error).message : t('profiles.discarded') });
    void load();
  };

  const name = version ? pick(version.payload.name, language) : key;
  return (
    <PanelShell permission="platform.profiles" title={name} testID="panel-profile">
      {error ? <ErrorState error={error} onRetry={() => void load()} /> : !detail || !version ? <Skeleton lines={8} /> : (
        <>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: space.sm }}>
            <Badge label={kind === 'pack' ? t('profiles.pack') : t('profiles.profile')} />
            <Badge label={version.status === 'published' ? t('profiles.published', { version: version.version }) : t('profiles.draft', { version: version.version })}
              tone={version.status === 'published' ? 'success' : 'warning'} testID="profile-version" />
          </View>
          <AppText>{pick(version.payload.description, language)}</AppText>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: space.sm }}>
            {text === null ? <Button icon="edit" label={draft ? t('profiles.editDraft') : t('profiles.newVersion')} onPress={openEditor} testID="profile-edit" /> : null}
            {draft ? <Button variant="tonal" icon="publish" label={t('profiles.publishDraft', { version: draft.version })} loading={busy}
              onPress={() => void publish()} testID="profile-publish" /> : null}
            {draft ? <Button variant="text" label={t('profiles.discard')} onPress={() => void discard()} testID="profile-discard" /> : null}
          </View>

          {problems ? (
            problems.length ? (
              <View style={{ gap: 4, padding: space.md, backgroundColor: colors.errorContainer, borderRadius: 12 }} testID="profile-problems">
                <AppText variant="titleSmall" style={{ color: colors.onErrorContainer }}>{t('profiles.problems', { count: problems.length })}</AppText>
                {problems.map((p) => <AppText key={p} variant="caption" style={{ color: colors.onErrorContainer }}>{p}</AppText>)}
              </View>
            ) : <Badge label={t('profiles.valid')} tone="success" icon="check-circle" testID="profile-valid" />
          ) : null}

          {text !== null ? (
            <Section title={t('profiles.editor')} testID="profile-editor">
              <AppText variant="caption">{t('profiles.editorHelp')}</AppText>
              {parsed && 'value' in parsed ? (
                <>
                  <TextField label={t('profiles.nameEn')} value={parsed.value.name?.en ?? ''} onChangeText={(v) => setName('en', v)} maxLength={120} testID="profile-name-en" />
                  <TextField label={t('profiles.nameBn')} value={parsed.value.name?.bn ?? ''} onChangeText={(v) => setName('bn', v)} maxLength={120} testID="profile-name-bn" />
                </>
              ) : null}
              <TextField label={t('profiles.json')} kind="multiline" value={text} onChangeText={(v) => { setText(v); setProblems(null); }}
                error={parsed && 'error' in parsed ? t('profiles.jsonInvalid', { error: parsed.error }) : null} testID="profile-json" />
              <TextField label={t('profiles.notes')} kind="multiline" value={notes} onChangeText={setNotes} maxLength={500} testID="profile-notes" />
              <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: space.sm }}>
                <Button variant="tonal" icon="rule" label={t('profiles.validate')} loading={busy} disabled={!parsed || !('value' in parsed)}
                  onPress={() => void validate()} testID="profile-validate" />
                <Button icon="save" label={t('profiles.saveDraft')} loading={busy} disabled={!parsed || !('value' in parsed)}
                  onPress={() => void save()} testID="profile-save" />
                <Button variant="text" label={t('profiles.cancel')} onPress={() => { setText(null); setProblems(null); }} testID="profile-cancel" />
              </View>
            </Section>
          ) : null}

          <Contents kind={kind} payload={version.payload} language={language} />

          <Section title={t('profiles.history')} testID="profile-history">
            {detail.versions.map((v: PackVersion) => (
              <Row key={v.version} icon={v.status === 'published' ? 'verified' : 'edit-note'} testID={`profile-v${v.version}`}
                title={v.status === 'published' ? t('profiles.published', { version: v.version }) : t('profiles.draft', { version: v.version })}
                subtitle={[v.published_at ? t('profiles.publishedBy', { date: format.dateTime(v.published_at), who: v.published_by ?? '—' })
                  : t('profiles.savedBy', { date: format.dateTime(v.created_at), who: v.created_by ?? '—' }), v.notes].filter(Boolean).join(' · ')}
                onPress={() => setShown(v.version)}
                badge={v.version === shown ? <Badge label={t('profiles.showing')} tone="primary" /> : undefined} />
            ))}
          </Section>
        </>
      )}
    </PanelShell>
  );
}

/** What a version sets, as lists (the main parts the owner reviews: words, stages, documents, fees, roles, modules). */
function Contents({ kind, payload, language }: { kind: PackKind; payload: PackPayload; language: string }) {
  const { t } = useTranslation('panel');
  const { space } = useTheme();
  const list = (items: unknown) => (Array.isArray(items) ? (items as Keyed[]) : []);
  const labels = Object.entries((payload.labels ?? {}) as Record<string, { en_singular: string; bn: { base: string } }>);
  const chips = (values: string[], testID: string) => (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: space.sm }} testID={testID}>
      {values.map((v, i) => <Badge key={`${v}-${i}`} label={v} />)}
    </View>
  );
  const fees = list((payload.fees as { heads?: unknown } | undefined)?.heads) as (Keyed & { frequency: string })[];
  const modules = kind === 'pack'
    ? list(payload.modules).map((m) => `${pick(m.name, language)}${(m as unknown as { default_on: boolean }).default_on ? '' : ` (${t('profiles.off')})`}`)
    : Object.entries((payload.modules ?? {}) as Record<string, boolean>).map(([k, on]) => `${k}: ${on ? t('profiles.on') : t('profiles.off')}`);
  return (
    <Section title={t('profiles.contents')} testID="profile-contents">
      <AppText variant="label">{t('profiles.words')}</AppText>
      {chips(labels.map(([k, v]) => `${k} → ${language === 'bn' ? v.bn.base : v.en_singular}`), 'profile-words')}
      <AppText variant="label">{t('profiles.stages')}</AppText>
      {chips(list(payload.stages).map((s) => pick(s.name, language)), 'profile-stages')}
      {kind === 'profile' ? (
        <>
          <AppText variant="label">{t('profiles.documents')}</AppText>
          {chips(list(payload.documents).map((d) => pick(d.name, language)), 'profile-documents')}
          <AppText variant="label">{t('profiles.fees')}</AppText>
          {chips(fees.map((f) => pick(f.name, language)), 'profile-fees')}
          <AppText variant="label">{t('profiles.roles')}</AppText>
          {chips([String(payload.role_template_set ?? '')], 'profile-roles')}
          <AppText variant="label">{t('profiles.clientNumber')}</AppText>
          {chips([String(payload.client_number_pattern ?? '')], 'profile-number')}
        </>
      ) : (
        <>
          <AppText variant="label">{t('profiles.fieldPresets')}</AppText>
          {chips(list(payload.field_presets).map((f) => pick(f.name, language)), 'profile-presets')}
          <AppText variant="label">{t('profiles.sensitive')}</AppText>
          {chips(list(payload.sensitive_fields).map((f) => String((f as unknown as { field: string }).field)), 'profile-sensitive')}
        </>
      )}
      <AppText variant="label">{t('profiles.modules')}</AppText>
      {chips(modules, 'profile-modules')}
    </Section>
  );
}
