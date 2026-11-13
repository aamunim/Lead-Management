import { useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import type { ErrorInfo } from '@/lib/errors';
import {
  markLiveTest, saveConnection, setConnectionActive, setConnectionSecret, settingsFields, type Connection, type Provider,
} from '@/lib/integrations';
import { useLanguageState } from '@/lib/language';
import { useFormat } from '@/lib/locale';
import { pick } from '@/lib/packs';
import { Badge, CheckRow, Chips, Row, SelectField, tDynamic } from '@/ui/admin/parts';
import { BottomSheet, Button, TextField, useSnackbar } from '@/ui/components';
import { useTheme } from '@/ui/theme';

// Connections (0B.11-T8; Ch 42, Ch 5.3 Providers / Integrations): each with its mode badge, status, key hints and age,
// live test, last success and last error with whose side it is on (I10). The sheet creates or changes one: settings
// form from the provider's schema, write-only secrets with an optional effective-from date (rotation).
export function ConnectionList({ connections, onOpen, testID }: { connections: Connection[]; onOpen?: (c: Connection) => void; testID?: string }) {
  const { t } = useTranslation('panel');
  const { language } = useLanguageState();
  const format = useFormat();
  if (connections.length === 0) return <AppText variant="caption" testID={testID ? `${testID}-empty` : undefined}>{t('integrations.none')}</AppText>;
  return (
    <View style={{ gap: 8 }} testID={testID}>
      {connections.map((c) => (
        <Row key={c.id} icon={c.status === 'disabled' ? 'link-off' : 'link'} title={`${c.label} · ${pick(c.provider_name, language)}`}
          testID={`connection-${c.label}`} onPress={onOpen ? () => onOpen(c) : undefined}
          subtitle={[
            tDynamic(`panel:integrations.kind.${c.kind}`), t('integrations.priority', { n: c.priority }),
            c.secrets?.map((s) => (s.hint ? t('integrations.keyHint', { field: s.field, hint: s.hint, days: s.age_days ?? 0 }) : t('integrations.keyMissing', { field: s.field }))).join(' · '),
            c.mode === 'live' ? (c.live_test_passed_at ? t('integrations.liveTested', { date: format.dateTime(c.live_test_passed_at) }) : t('integrations.liveUntested')) : null,
            c.last_success_at ? t('integrations.lastSuccess', { date: format.dateTime(c.last_success_at) }) : null,
            c.last_error ? t('integrations.lastError', { code: c.last_error.code, side: tDynamic(`panel:integrations.side.${c.last_error.responsibility}`) }) : null,
            c.adapter_ready ? null : t('integrations.adapterLater'),
          ].filter(Boolean).join(' · ')}
          badge={<View style={{ flexDirection: 'row', gap: 4 }}>
            <Badge label={tDynamic(`panel:integrations.mode.${c.mode}`)} tone={c.mode === 'live' ? 'success' : 'warning'} />
            {c.status === 'disabled' ? <Badge label={t('integrations.disabled')} tone="error" /> : null}
          </View>} />
      ))}
    </View>
  );
}

export function ConnectionSheet({ institutionId, providers, connection, onClose, onSaved }: {
  institutionId: string | null; providers: Provider[]; connection: Connection | null; onClose: () => void; onSaved: () => void;
}) {
  const { t } = useTranslation('panel');
  const { language } = useLanguageState();
  const { space } = useTheme();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [provider, setProvider] = useState<string | null>(connection?.provider ?? null);
  const [form, setForm] = useState({ label: connection?.label ?? '', mode: connection?.mode ?? 'sandbox', priority: String(connection?.priority ?? 1) });
  const [settings, setSettings] = useState<Record<string, unknown>>(connection?.settings ?? {});
  const [secret, setSecret] = useState<{ field: string; value: string; from: string }>({ field: '', value: '', from: '' });
  const [busy, setBusy] = useState(false);
  const p = providers.find((x) => x.key === provider) ?? null;
  const fields = p ? settingsFields(p.settings_schema) : [];

  const run = async (fn: () => Promise<{ error: ErrorInfo | null }>, done: string) => {
    setBusy(true);
    const r = await fn();
    setBusy(false);
    if (r.error) return snackbar.show({ text: errorText(r.error).message });
    snackbar.show({ text: done });
    onSaved();
  };
  const save = () => run(() => saveConnection(institutionId, connection?.id ?? null, {
    provider: provider ?? '', label: form.label.trim(), mode: form.mode, priority: Number(form.priority) || 1, settings,
  }), t('integrations.saved'));

  return (
    <BottomSheet visible onClose={onClose} title={connection ? t('integrations.edit', { label: connection.label }) : t('integrations.add')} testID="connection-sheet"
      footer={<Button label={t('integrations.save')} loading={busy} fullWidth disabled={!provider || !form.label.trim()} onPress={() => void save()}
        testID="connection-save" />}>
      {connection ? null : (
        <SelectField label={t('integrations.provider')} value={provider} testID="connection-provider"
          choices={providers.filter((x) => x.status !== 'retired').map((x) => ({ value: x.key, label: `${pick(x.name, language)} (${tDynamic(`panel:integrations.kind.${x.kind}`)})`,
            testID: `connection-provider-${x.key}` }))}
          onChange={(v) => { setProvider(v); setSettings({}); }} />
      )}
      <TextField label={t('integrations.label')} value={form.label} maxLength={80} onChangeText={(v) => setForm((f) => ({ ...f, label: v }))} testID="connection-label" />
      <Chips label={t('integrations.modeLabel')} selected={form.mode} onSelect={(v) => setForm((f) => ({ ...f, mode: v }))}
        choices={(['sandbox', 'live'] as const).map((m) => ({ value: m, label: tDynamic(`panel:integrations.mode.${m}`), testID: `connection-mode-${m}` }))} />
      <Chips label={t('integrations.priorityLabel')} selected={form.priority} onSelect={(v) => setForm((f) => ({ ...f, priority: v }))}
        choices={['1', '2', '3'].map((n) => ({ value: n, label: t('integrations.priority', { n: Number(n) }), testID: `connection-priority-${n}` }))} />
      {fields.map((f) => f.kind === 'boolean' ? (
        <CheckRow key={f.key} label={f.key} checked={settings[f.key] === true} onToggle={() => setSettings((s) => ({ ...s, [f.key]: !(s[f.key] === true) }))}
          testID={`connection-setting-${f.key}`} />
      ) : f.kind === 'choice' ? (
        <Chips key={f.key} label={f.key} selected={String(settings[f.key] ?? f.schema.default ?? '')} onSelect={(v) => setSettings((s) => ({ ...s, [f.key]: v }))}
          choices={(f.choices ?? []).map((c) => ({ value: c, label: c, testID: `connection-setting-${f.key}-${c}` }))} />
      ) : (
        <TextField key={f.key} label={f.key} required={f.required} kind={f.kind === 'number' ? 'number' : 'text'} value={String(settings[f.key] ?? '')}
          onChangeText={(v) => setSettings((s) => {
            const next = { ...s };
            if (v === '') delete next[f.key];
            else next[f.key] = f.kind === 'number' ? Number(v) : v;
            return next;
          })} testID={`connection-setting-${f.key}`} />
      ))}
      {connection && p ? (
        <View style={{ gap: space.sm }} testID="connection-secrets">
          <AppText variant="label">{t('integrations.secrets')}</AppText>
          <AppText variant="caption">{t('integrations.secretsHelp')}</AppText>
          <Chips label={t('integrations.secretField')} selected={secret.field} onSelect={(v) => setSecret((s) => ({ ...s, field: v }))}
            choices={p.secret_fields.map((f) => ({ value: f, label: f, testID: `secret-field-${f}` }))} />
          <TextField label={t('integrations.secretValue')} kind="password" value={secret.value} onChangeText={(v) => setSecret((s) => ({ ...s, value: v }))}
            testID="secret-value" />
          <TextField label={t('integrations.secretFrom')} value={secret.from} help={t('integrations.secretFromHelp')} maxLength={10}
            onChangeText={(v) => setSecret((s) => ({ ...s, from: v }))} testID="secret-from" />
          <Button variant="tonal" icon="key" label={t('integrations.secretSave')} loading={busy} disabled={!secret.field || secret.value.length < 4}
            onPress={() => void run(async () => {
              const r = await setConnectionSecret(institutionId, connection.id, secret.field, secret.value,
                /^\d{4}-\d{2}-\d{2}$/.test(secret.from) ? `${secret.from}T00:00:00Z` : null);
              if (!r.error) setSecret({ field: '', value: '', from: '' });
              return r;
            }, t('integrations.secretSaved'))} testID="secret-save" />
          {connection.mode === 'live' ? (
            <Button variant="tonal" icon="verified" label={connection.live_test_passed_at ? t('integrations.liveClear') : t('integrations.liveMark')} loading={busy}
              onPress={() => void run(() => markLiveTest(institutionId, connection.id, !connection.live_test_passed_at, null), t('integrations.saved'))}
              testID="connection-live-test" />
          ) : null}
          <Button variant={connection.status === 'active' ? 'danger' : 'tonal'} icon={connection.status === 'active' ? 'link-off' : 'link'}
            label={connection.status === 'active' ? t('integrations.disable') : t('integrations.enable')} loading={busy}
            onPress={() => void run(() => setConnectionActive(institutionId, connection.id, connection.status !== 'active', null), t('integrations.saved'))}
            testID="connection-toggle" />
        </View>
      ) : null}
    </BottomSheet>
  );
}
