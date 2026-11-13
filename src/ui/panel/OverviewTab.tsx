import { router } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { useLanguageState } from '@/lib/language';
import { NEXT, createExport, fetchOverview, getExport, saveJson, setStatus, type InstitutionStatus, type Overview } from '@/lib/lifecycle';
import { useFormat } from '@/lib/locale';
import { pick } from '@/lib/packs';
import { applyCopy, COPY_AREAS, fetchPlatformChecklist, markPlatformChecklist, previewCopy, type Checklist, type CopyArea } from '@/lib/setup';
import { fetchInstitutionInvites } from '@/lib/signup';
import { startSupport } from '@/lib/support';
import { Badge, CheckRow, Chips, Row, Section, SelectField, tDynamic } from '@/ui/admin/parts';
import { BottomSheet, Button, ErrorState, Skeleton, TextField, useSnackbar } from '@/ui/components';
import { ChecklistView } from '@/ui/setup/ChecklistView';
import { fetchPanelInstitutions, type PanelInstitution } from '@/lib/platform-institutions';

import { usePanel } from './PanelContext';

// Institution → Overview (0B.07-T9; Ch 5.4): information, status with its history, problems, types, usage, Super
// Admins, last sign-in, duplicate and trial warnings, full exports, and the status actions (approve, read only,
// suspend, reactivate, close after a full export), and "Enter institution" (0B.08: reason + time limit, read only).
export function OverviewTab({ institutionId, onChanged }: { institutionId: string; onChanged?: () => void }) {
  const { t } = useTranslation('panel');
  const { language } = useLanguageState();
  const format = useFormat();
  const { can } = usePanel();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [data, setData] = useState<Overview | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [change, setChange] = useState<InstitutionStatus | null>(null);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [entering, setEntering] = useState(false);
  const [entry, setEntry] = useState({ reason: '', minutes: '30' });
  const [invites, setInvites] = useState<{ id: string; email: string; invited_at: string; accepted_at: string | null }[]>([]);
  const [checklist, setChecklist] = useState<Checklist | null>(null);
  const [copying, setCopying] = useState<{ sources: PanelInstitution[]; source: string | null; areas: string[]; preview: CopyArea[] | null } | null>(null);

  const load = useCallback(async () => {
    setError(null);
    const r = await fetchOverview(institutionId);
    if (r.error) setError(r.error);
    else setData(r.data);
    const inv = await fetchInstitutionInvites(institutionId);
    setInvites(inv.data ?? []);
    const cl = await fetchPlatformChecklist(institutionId);
    setChecklist(cl.data);
  }, [institutionId]);
  useEffect(() => {
    void load();
  }, [load]);

  if (error) return <ErrorState error={error} onRetry={() => void load()} />;
  if (!data) return <Skeleton lines={8} />;
  const i = data.institution;
  const allowed = (s: InstitutionStatus) => (s === 'closed' ? can('platform.institutions_close') : can('platform.institutions'));
  const apply = async () => {
    if (!change) return;
    setBusy(true);
    const r = await setStatus(institutionId, change, reason.trim() || null);
    setBusy(false);
    snackbar.show({ text: r.error ? errorText(r.error).message : t('overview.statusChanged') });
    if (!r.error) {
      setChange(null);
      setReason('');
      onChanged?.();
      void load();
    }
  };
  const enter = async () => {
    setBusy(true);
    const r = await startSupport(institutionId, entry.reason.trim(), Number(entry.minutes));
    setBusy(false);
    if (r.error) return snackbar.show({ text: errorText(r.error).message });
    router.replace('/home');
  };
  const markItem = async (item: string, done: boolean) => {
    setBusy(true);
    const r = await markPlatformChecklist(institutionId, item, done);
    setBusy(false);
    if (r.error) return snackbar.show({ text: errorText(r.error).message });
    setChecklist(r.data);
  };
  const openCopy = async () => {
    const r = await fetchPanelInstitutions();
    if (r.error) return snackbar.show({ text: errorText(r.error).message });
    setCopying({ sources: (r.data ?? []).filter((x) => x.id !== institutionId), source: null, areas: [...COPY_AREAS], preview: null });
  };
  const runCopy = async (confirm: boolean) => {
    if (!copying?.source) return;
    setBusy(true);
    const r = confirm ? await applyCopy(institutionId, copying.source, copying.areas) : await previewCopy(institutionId, copying.source, copying.areas);
    setBusy(false);
    if (r.error || !r.data) return snackbar.show({ text: r.error ? errorText(r.error).message : '' });
    if (confirm) {
      snackbar.show({ text: t('copy.done') });
      setCopying(null);
      void load();
    } else setCopying({ ...copying, preview: r.data.areas });
  };
  const makeExport = async () => {
    setBusy(true);
    const r = await createExport(institutionId);
    setBusy(false);
    snackbar.show({ text: r.error ? errorText(r.error).message : t('overview.exportMade') });
    void load();
  };
  const download = async (id: string, at: string) => {
    const r = await getExport(id, institutionId);
    if (r.error) return snackbar.show({ text: errorText(r.error).message });
    if (!saveJson(`${i.slug}-${at.slice(0, 10)}.json`, r.data)) snackbar.show({ text: t('overview.webOnly') });
  };

  return (
    <View style={{ gap: 16 }} testID="overview-tab">
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
        <Badge label={tDynamic(`panel:institutions.status.${i.status}`)} tone={i.status === 'active' || i.status === 'trial' ? 'success' : 'warning'}
          testID="overview-status" />
        {data.problems.map((p) => <Badge key={p} label={tDynamic(`panel:overview.problems.${p}`)} tone="error" />)}
      </View>
      <Section title={t('overview.info')} testID="overview-info">
        <AppText>{[i.slug, i.eiin ? t('overview.eiin', { value: i.eiin }) : null, i.institution_code ? t('overview.code', { value: i.institution_code }) : null]
          .filter(Boolean).join(' · ')}</AppText>
        {i.address ? <AppText variant="caption">{i.address}</AppText> : null}
        <AppText variant="caption">{[i.contact_phone, t('overview.created', { date: format.dateTime(i.created_at) }),
          data.last_login ? t('overview.lastLogin', { date: format.dateTime(data.last_login) }) : t('overview.neverLoggedIn')].filter(Boolean).join(' · ')}</AppText>
        <AppText variant="caption">{t('overview.types', { names: data.profiles.map((p) => pick(p.name, language)).join(' + ') || '—' })}</AppText>
        <AppText variant="caption">{t('overview.superAdmins', { emails: data.super_admins.join(', ') || '—' })}</AppText>
        <AppText variant="caption">{data.usage.filter((u) => u.used > 0).map((u) => `${tDynamic(`admin:limits.metrics.${u.metric}`)}: ${u.limit === null ? u.used : `${u.used}/${u.limit}`}`).join(' · ')}</AppText>
        {can('platform.support_access') && i.status !== 'closed' ? (
          <Button variant="tonal" icon="login" label={t('overview.enter')} onPress={() => setEntering(true)} testID="overview-enter" />
        ) : null}
      </Section>

      {checklist ? (
        <Section title={t('overview.checklist')} testID="overview-checklist"
          action={can('platform.institutions') ? <Button variant="text" icon="content-copy" label={t('copy.open')} onPress={() => void openCopy()}
            testID="overview-copy" /> : undefined}>
          <ChecklistView list={checklist} busy={busy} canMark={(item) => can('platform.institutions') && item.owner !== 'super_admin'}
            onMark={(item, done) => void markItem(item.key, done)} />
        </Section>
      ) : null}

      {invites.length ? (
        <Section title={t('create.invites')} testID="overview-invites">
          {invites.map((v) => (
            <Row key={v.id} icon={v.accepted_at ? 'how-to-reg' : 'schedule'} title={t(v.accepted_at ? 'create.inviteAccepted' : 'create.inviteOpen', { email: v.email })}
              subtitle={format.dateTime(v.accepted_at ?? v.invited_at)} testID={`overview-invite-${v.email}`} />
          ))}
        </Section>
      ) : null}

      {data.duplicates.length || data.trial.flagged ? (
        <Section title={t('overview.warnings')} testID="overview-warnings">
          {data.duplicates.map((d) => <Row key={d.id} icon="content-copy" title={d.name} subtitle={tDynamic(`panel:overview.match.${d.match}`)} />)}
          {data.trial.flagged ? <AppText testID="overview-trial-flag">{t('overview.trialFlag', { person: data.trial.by_person, phone: data.trial.by_phone, limit: data.trial.limit })}</AppText> : null}
        </Section>
      ) : null}

      <Section title={t('overview.status')} testID="overview-actions">
        {NEXT[i.status].filter(allowed).length ? (
          <Chips label={t('overview.changeTo')} selected={change ?? i.status} onSelect={(v) => setChange(v === i.status ? null : v)}
            choices={[i.status, ...NEXT[i.status].filter(allowed)].map((s) => ({ value: s, label: tDynamic(`panel:overview.to.${s}`), testID: `overview-to-${s}` }))} />
        ) : <AppText variant="caption">{t('overview.noChange')}</AppText>}
        {i.purge_after ? <AppText testID="overview-purge">{t('overview.purgeOn', { date: format.dateTime(i.purge_after) })}</AppText> : null}
        {data.history.map((h) => (
          <Row key={h.at} icon="history" title={`${h.from ? tDynamic(`panel:institutions.status.${h.from}`) : '—'} → ${tDynamic(`panel:institutions.status.${h.to}`)}`}
            subtitle={[format.dateTime(h.at), h.by, h.reason].filter(Boolean).join(' · ')} />
        ))}
      </Section>

      <Section title={t('overview.exports')} testID="overview-exports">
        <AppText variant="caption">{t('overview.exportsHelp')}</AppText>
        {can('platform.institutions') ? <Button variant="tonal" icon="download" label={t('overview.makeExport')} loading={busy} onPress={() => void makeExport()}
          testID="overview-export-make" /> : null}
        {data.exports.map((e) => (
          <Row key={e.id} icon="inventory" title={format.dateTime(e.created_at)} subtitle={t('overview.size', { kb: format.number(Math.ceil(e.size_bytes / 1024)) })}
            onPress={() => void download(e.id, e.created_at)} testID={`overview-export-${e.id}`} />
        ))}
      </Section>

      {copying ? (
        <BottomSheet visible onClose={() => setCopying(null)} title={t('copy.title', { name: i.name })} testID="copy-sheet"
          footer={copying.preview ? <Button label={t('copy.confirm')} loading={busy} fullWidth onPress={() => void runCopy(true)} testID="copy-confirm" />
            : <Button variant="tonal" label={t('copy.preview')} loading={busy} fullWidth disabled={!copying.source || copying.areas.length === 0}
              onPress={() => void runCopy(false)} testID="copy-preview" />}>
          <AppText>{t('copy.help')}</AppText>
          <SelectField label={t('copy.source')} value={copying.source} testID="copy-source"
            choices={copying.sources.map((x) => ({ value: x.id, label: x.name, testID: `copy-source-${x.slug}` }))}
            onChange={(v) => setCopying({ ...copying, source: v, preview: null })} />
          {COPY_AREAS.map((a) => (
            <CheckRow key={a} label={tDynamic(`panel:copy.areas.${a}`)} checked={copying.areas.includes(a)} testID={`copy-area-${a}`}
              help={copying.preview?.find((p) => p.area === a) ? t('copy.counts', { add: copying.preview.find((p) => p.area === a)?.add ?? 0,
                keep: copying.preview.find((p) => p.area === a)?.keep ?? 0 }) : undefined}
              onToggle={() => setCopying({ ...copying, preview: null,
                areas: copying.areas.includes(a) ? copying.areas.filter((x) => x !== a) : [...copying.areas, a] })} />
          ))}
        </BottomSheet>
      ) : null}
      {entering ? (
        <BottomSheet visible onClose={() => setEntering(false)} title={t('overview.enterTitle', { name: i.name })} testID="enter-sheet"
          footer={<Button label={t('overview.enterConfirm')} loading={busy} fullWidth disabled={entry.reason.trim().length < 5}
            onPress={() => void enter()} testID="enter-confirm" />}>
          <AppText>{t('overview.enterHelp')}</AppText>
          <TextField label={t('overview.enterReason')} kind="multiline" value={entry.reason} maxLength={500}
            onChangeText={(v) => setEntry((e) => ({ ...e, reason: v }))} testID="enter-reason" />
          <Chips label={t('overview.enterMinutes')} selected={entry.minutes} onSelect={(v) => setEntry((e) => ({ ...e, minutes: v }))}
            choices={['15', '30', '60', '120'].map((m) => ({ value: m, label: t('overview.minutes', { count: Number(m) }), testID: `enter-minutes-${m}` }))} />
        </BottomSheet>
      ) : null}
      {change ? (
        <BottomSheet visible onClose={() => setChange(null)} title={t('overview.confirmTitle', { status: tDynamic(`panel:institutions.status.${change}`) })}
          testID="status-sheet"
          footer={<Button variant={change === 'closed' || change === 'suspended' ? 'danger' : 'filled'} label={t('overview.confirm')} loading={busy} fullWidth
            onPress={() => void apply()} testID="status-confirm" />}>
          <AppText>{tDynamic(`panel:overview.explain.${change}`)}</AppText>
          {change === 'closed' && !data.can_close_now ? <AppText testID="status-needs-export">{t('overview.needsExport')}</AppText> : null}
          <TextField label={t('overview.reason')} kind="multiline" value={reason} onChangeText={setReason} maxLength={500} testID="status-reason" />
        </BottomSheet>
      ) : null}
    </View>
  );
}
