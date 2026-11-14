import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { addEmailDomain, fetchEmail, resumeEmail, verifyEmailDomain, type EmailState } from '@/lib/integrations';
import { useFormat } from '@/lib/locale';
import { Badge, Chips, Row, Section, tDynamic } from '@/ui/admin/parts';
import { Button, TextField, useSnackbar } from '@/ui/components';
import { useTheme } from '@/ui/theme';

import { usePanel } from './PanelContext';

// Institution → Integrations → Email (0B.14; Ch 42.5): sending domains with step-by-step DNS records and Verify, the
// platform mail sender (the institution's own address, never another's), bounce / complaint numbers for 7 days, and a
// paused sender with Resume (a reason is required).
export function EmailSection({ institutionId }: { institutionId: string }) {
  const { t } = useTranslation('panel');
  const format = useFormat();
  const { colors, radius, space } = useTheme();
  const { can } = usePanel();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const manage = can('platform.integrations');
  const [data, setData] = useState<EmailState | null>(null);
  const [domain, setDomain] = useState({ name: '', provider: 'resend' as 'resend' | 'smtp' });
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async () => {
    const r = await fetchEmail(institutionId);
    if (!r.error) setData(r.data);
  }, [institutionId]);
  useEffect(() => {
    void load();
  }, [load]);
  if (!data) return null;
  const rep = data.reputation;

  return (
    <Section title={t('email.title')} testID="email-section">
      <AppText variant="caption">{t('email.help')}</AppText>
      {data.paused ? (
        <View style={{ padding: space.md, borderRadius: radius.md, backgroundColor: colors.errorContainer, gap: space.sm }} testID="email-paused">
          <AppText style={{ color: colors.onErrorContainer }}>{t('email.paused', { reason: data.paused.reason, date: format.dateTime(data.paused.at) })}</AppText>
          {manage ? (
            <>
              <TextField label={t('email.resumeReason')} value={reason} onChangeText={setReason} maxLength={300} testID="email-resume-reason" />
              <Button variant="tonal" label={t('email.resume')} loading={busy === 'resume'} disabled={reason.trim().length < 3} testID="email-resume"
                onPress={async () => {
                  setBusy('resume');
                  const r = await resumeEmail(institutionId, reason.trim());
                  setBusy(null);
                  if (r.error) return snackbar.show({ text: errorText(r.error).message });
                  setReason('');
                  setData(r.data);
                }} />
            </>
          ) : null}
        </View>
      ) : null}
      <AppText variant="caption" testID="email-reputation">{t('email.reputation', rep)}</AppText>
      <AppText variant="caption" testID="email-platform-sender">
        {data.platform_sender?.from_email ? t('email.platformSender', { from: data.platform_sender.from_email }) : t('email.noPlatformSender')}
      </AppText>
      {data.domains.map((d) => (
        <View key={d.domain} style={{ gap: space.xs }} testID={`email-domain-${d.domain}`}>
          <Row icon="dns" title={d.domain} subtitle={[tDynamic(`panel:email.providers.${d.provider ?? 'smtp'}`),
            d.checked_at ? t('email.checked', { date: format.dateTime(d.checked_at) }) : t('email.notChecked')].join(' · ')}
            badge={<Badge label={tDynamic(`panel:email.status.${d.status}`)} tone={d.status === 'verified' ? 'success' : d.status === 'failed' ? 'error' : 'warning'} />} />
          {d.expected.map((rec, i) => {
            const check = d.last_check?.[rec.check];
            return (
              <AppText key={rec.check} variant="caption" testID={`email-record-${d.domain}-${rec.check}`}>
                {`${i + 1}. ${rec.type} ${rec.name} → ${rec.value}${check ? ` — ${check.ok ? t('email.recordOk') : check.problem ?? t('email.recordMissing')}` : ''}`}
              </AppText>
            );
          })}
          {manage ? (
            <Button variant="tonal" icon="verified" label={t('email.verify')} loading={busy === d.domain} testID={`email-verify-${d.domain}`}
              onPress={async () => {
                setBusy(d.domain);
                const r = await verifyEmailDomain(institutionId, d.domain);
                setBusy(null);
                snackbar.show({ text: r.error ? t('email.verifyFailed') : tDynamic(`panel:email.status.${r.data?.status ?? 'pending'}`) });
                void load();
              }} />
          ) : null}
        </View>
      ))}
      {manage ? (
        <View style={{ gap: space.xs }}>
          <TextField label={t('email.domain')} value={domain.name} onChangeText={(v) => setDomain((d) => ({ ...d, name: v.trim() }))} help={t('email.domainHelp')}
            testID="email-domain-input" />
          <Chips label={t('email.provider')} selected={domain.provider} onSelect={(v) => setDomain((d) => ({ ...d, provider: v }))}
            choices={(['resend', 'smtp'] as const).map((p) => ({ value: p, label: tDynamic(`panel:email.providers.${p}`), testID: `email-provider-${p}` }))} />
          <Button variant="tonal" icon="add" label={t('email.addDomain')} loading={busy === 'add'} disabled={!domain.name.includes('.')} testID="email-domain-add"
            onPress={async () => {
              setBusy('add');
              const r = await addEmailDomain(institutionId, domain.name, domain.provider, null);
              setBusy(null);
              if (r.error) return snackbar.show({ text: errorText(r.error).message });
              setDomain({ name: '', provider: domain.provider });
              setData(r.data);
            }} />
        </View>
      ) : null}
    </Section>
  );
}
