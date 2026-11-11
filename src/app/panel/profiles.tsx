import { router } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { useLanguageState } from '@/lib/language';
import { fetchPacks, pick, setIndustryOpen, type IndustryRow } from '@/lib/packs';
import { Badge, CheckRow, Row, Section } from '@/ui/admin/parts';
import { ErrorState, Skeleton, useSnackbar } from '@/ui/components';
import { usePanel } from '@/ui/panel/PanelContext';
import { PanelShell } from '@/ui/panel/PanelShell';

// Profiles and packs (0B.03-T9): the industry list (which are open for sign-up), each industry's pack and type
// profiles with their published and draft versions. Opening an industry needs its published pack and a profile.
export default function PanelProfiles() {
  const { t } = useTranslation('panel');
  const { language } = useLanguageState();
  const { state } = usePanel();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [rows, setRows] = useState<IndustryRow[] | null>(null);
  const [error, setError] = useState<unknown>(null);

  const load = useCallback(async () => {
    setError(null);
    const r = await fetchPacks();
    if (r.error) setError(r.error);
    else setRows(r.data ?? []);
  }, []);
  useEffect(() => {
    if (state.status === 'ready') void load();
  }, [state.status, load]);

  const versionText = (v: { published_version: number | null; draft_version: number | null } | null) =>
    [v?.published_version ? t('profiles.published', { version: v.published_version }) : t('profiles.notPublished'),
      v?.draft_version ? t('profiles.draft', { version: v.draft_version }) : null].filter(Boolean).join(' · ');
  const toggle = async (row: IndustryRow) => {
    const r = await setIndustryOpen(row.key, !row.signup_open);
    snackbar.show({ text: r.error ? errorText(r.error).message : t('profiles.saved') });
    void load();
  };

  return (
    <PanelShell permission="platform.profiles" title={t('menu.profiles')} testID="panel-profiles">
      <AppText>{t('profiles.intro')}</AppText>
      {error ? <ErrorState error={error} onRetry={() => void load()} /> : !rows ? <Skeleton lines={6} /> : (
        <>
          {rows.filter((r) => r.pack).map((row) => (
            <Section key={row.key} title={pick(row.name, language)} testID={`industry-${row.key}`}>
              <Row icon="inventory-2" title={t('profiles.pack')} subtitle={versionText(row.pack)} testID={`pack-${row.key}`}
                onPress={() => router.push(`/panel/profile/pack/${row.key}`)}
                badge={row.pack?.draft_version ? <Badge label={t('profiles.hasDraft')} tone="warning" /> : undefined} />
              <AppText variant="label">{t('profiles.typeProfiles', { count: row.profiles.length })}</AppText>
              <View style={{ gap: 8 }}>
                {row.profiles.map((p) => (
                  <Row key={p.key} icon="category" title={pick(p.name, language)} subtitle={versionText(p)} testID={`profile-${p.key}`}
                    onPress={() => router.push(`/panel/profile/profile/${p.key}`)}
                    badge={p.draft_version ? <Badge label={t('profiles.hasDraft')} tone="warning" /> : undefined} />
                ))}
              </View>
            </Section>
          ))}
          <Section title={t('profiles.signup')} testID="industries">
            <AppText variant="caption">{t('profiles.signupHelp')}</AppText>
            {rows.map((row) => (
              <CheckRow key={row.key} label={pick(row.name, language)} checked={row.signup_open} onToggle={() => void toggle(row)}
                disabled={!row.pack?.published_version} help={row.pack?.published_version ? undefined : t('profiles.noPack')}
                testID={`industry-open-${row.key}`} />
            ))}
          </Section>
        </>
      )}
    </PanelShell>
  );
}
