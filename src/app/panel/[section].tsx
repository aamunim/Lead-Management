import { useLocalSearchParams } from 'expo-router';

import { useTranslation } from '@/i18n';
import { EmptyState } from '@/ui/components';
import { PANEL_MENU } from '@/ui/panel/menu';
import { PanelShell } from '@/ui/panel/PanelShell';
import { tDynamic } from '@/ui/admin/parts';

// Panel pages built by later milestones (0B.02-T6): the menu entry exists now and says when it arrives.
export default function PanelSection() {
  const { section } = useLocalSearchParams<{ section: string }>();
  const { t } = useTranslation('panel');
  const item = PANEL_MENU.find((i) => i.key === section);
  if (!item) return <PanelShell permission="platform.view" title={t('title')}><EmptyState icon="help-outline" title={t('noAccess')} /></PanelShell>;
  return (
    <PanelShell permission={item.permission} title={tDynamic(`panel:menu.${item.key}`)} testID={`panel-${item.key}`}>
      <EmptyState icon="construction" title={t('soon', { milestone: item.builtIn ?? '' })} testID={`panel-${item.key}-soon`} />
    </PanelShell>
  );
}
