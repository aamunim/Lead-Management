import { router, type Href } from 'expo-router';
import { View } from 'react-native';

import { useTranslation } from '@/i18n';
import { useMyAccess } from '@/lib/access';
import { useModulesEnabled } from '@/lib/modules';
import { useSetting } from '@/lib/settings';
import { Row } from '@/ui/admin/parts';
import { EmptyState, ErrorState, Screen, Skeleton, type IconName } from '@/ui/components';
import { useTheme } from '@/ui/theme';

// Settings (0A.18): only the screens the person's roles allow are shown (the server checks again on every call).
// Branches / Terminology (0A.19) and the institution settings (0B) join this list later.
export default function SettingsTab() {
  const { t } = useTranslation('admin');
  const { space } = useTheme();
  const { loaded, error, retry, can } = useMyAccess();
  // With branches off, nothing about branches appears anywhere (Ch 12.2).
  const modules = useModulesEnabled();
  const branchesOn = useSetting<boolean>('branches_enabled', false) === true && modules.enabled('branches');
  type Item = { href: Href; title: string; help: string; icon: IconName; testID: string; show: boolean };
  const all: Item[] = [
    { href: '/admin/users', title: t('menu.users'), help: t('menu.usersHelp'), icon: 'group', testID: 'settings-users', show: can('settings.users') },
    { href: '/admin/roles', title: t('menu.roles'), help: t('menu.rolesHelp'), icon: 'admin-panel-settings', testID: 'settings-roles',
      show: can('settings.roles') },
    { href: '/admin/explain', title: t('menu.explain'), help: t('menu.explainHelp'), icon: 'help-outline', testID: 'settings-explain',
      show: can('settings.users') },
    { href: '/admin/branches', title: t('menu.branches'), help: t('menu.branchesHelp'), icon: 'store', testID: 'settings-branches',
      show: branchesOn && can('settings.organisation') },
    { href: '/admin/terminology', title: t('menu.terminology'), help: t('menu.terminologyHelp'), icon: 'translate', testID: 'settings-terminology',
      show: can('settings.terminology') },
    { href: '/admin/institution-type', title: t('menu.types'), help: t('menu.typesHelp'), icon: 'category', testID: 'settings-types',
      show: can('settings.institution_type') },
    { href: '/admin/custom-fields', title: t('menu.fields'), help: t('menu.fieldsHelp'), icon: 'dynamic-form', testID: 'settings-fields',
      show: can('settings.custom_fields') },
    { href: '/admin/modules', title: t('menu.modules'), help: t('menu.modulesHelp'), icon: 'extension', testID: 'settings-modules',
      show: can('settings.modules') },
    { href: '/admin/plan', title: t('menu.plan'), help: t('menu.planHelp'), icon: 'workspace-premium', testID: 'settings-plan',
      show: can('billing.view') },
    { href: '/admin/support-log', title: t('menu.supportLog'), help: t('menu.supportLogHelp'), icon: 'support-agent', testID: 'settings-support-log',
      show: can('settings.security') },
    { href: '/admin/audit', title: t('menu.audit'), help: t('menu.auditHelp'), icon: 'history', testID: 'settings-audit', show: can('audit.view') },
  ];
  const items = all.filter((i) => i.show);
  return (
    <Screen title={t('menu.title')} intro={items.length ? t('menu.intro') : undefined} testID="settings">
      {error ? <ErrorState error={error} onRetry={retry} testID="settings-error" /> : !loaded ? <Skeleton lines={3} testID="settings-loading" /> : items.length === 0 ? (
        <EmptyState icon="lock-outline" title={t('menu.nothing')} body={t('menu.nothingBody')} testID="settings-empty" />
      ) : (
        <View style={{ gap: space.sm }}>
          {items.map((i) => <Row key={i.testID} title={i.title} subtitle={i.help} icon={i.icon} onPress={() => router.push(i.href)} testID={i.testID} />)}
        </View>
      )}
    </Screen>
  );
}
