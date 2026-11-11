import { router } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useLanguageState } from '@/lib/language';
import { pick } from '@/lib/packs';
import { fetchPanelInstitutions, type PanelInstitution } from '@/lib/platform-institutions';
import { Row, tDynamic } from '@/ui/admin/parts';
import { Button, ErrorState, Skeleton, TextField } from '@/ui/components';
import { usePanel } from '@/ui/panel/PanelContext';
import { PanelShell } from '@/ui/panel/PanelShell';

// Institutions (0B.04: list and the Labels tab; the other tabs, approval and status come with 0B.07).
export default function PanelInstitutions() {
  const { t } = useTranslation('panel');
  const { language } = useLanguageState();
  const { state, can } = usePanel();
  const [rows, setRows] = useState<PanelInstitution[] | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [query, setQuery] = useState('');

  const load = useCallback(async () => {
    setError(null);
    const r = await fetchPanelInstitutions();
    if (r.error) setError(r.error);
    else setRows(r.data ?? []);
  }, []);
  useEffect(() => {
    if (state.status === 'ready') void load();
  }, [state.status, load]);
  const q = query.trim().toLowerCase();
  const shown = (rows ?? []).filter((r) => !q || r.name.toLowerCase().includes(q) || r.slug.includes(q));

  return (
    <PanelShell permission="platform.view" title={t('menu.institutions')} testID="panel-institutions">
      <AppText>{t('institutions.intro')}</AppText>
      {can('platform.plans') ? <Button variant="tonal" icon="workspace-premium" label={t('plans.title')} onPress={() => router.push('/panel/plans')}
        testID="institutions-plans" /> : null}
      <TextField label={t('institutions.search')} kind="search" value={query} onChangeText={setQuery} testID="institutions-search" />
      {error ? <ErrorState error={error} onRetry={() => void load()} /> : !rows ? <Skeleton lines={6} /> : (
        <View style={{ gap: 8 }}>
          {shown.map((i) => (
            <Row key={i.id} icon="apartment" title={i.name} testID={`institution-${i.slug}`}
              subtitle={[tDynamic(`panel:institutions.status.${i.status}`),
                i.profiles.length ? i.profiles.map((p) => pick(p.name, language)).join(' + ') : t('institutions.noTypes')].join(' · ')}
              onPress={() => router.push(`/panel/institution/${i.id}`)} />
          ))}
        </View>
      )}
    </PanelShell>
  );
}
