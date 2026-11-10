import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { fetchRegistry, fetchRoles } from '@/lib/admin';
import { grantOf, newestRelease, type PermissionInfo, type RoleInfo } from '@/lib/admin-core';
import { Badge, permissionHelp, permissionLabel, roleName } from '@/ui/admin/parts';
import { EmptyState, ErrorState, Screen, Skeleton } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// "New permissions in this release" (0A.18-T5, R20): what arrived, and which of the institution's roles received it
// by the rollout rule (template defaults; inheriting own roles only when not sensitive), so the admin can check.
export default function NewPermissionsScreen() {
  const { t } = useTranslation('admin');
  const { colors, space } = useTheme();
  const [data, setData] = useState<{ roles: RoleInfo[]; permissions: PermissionInfo[] } | null>(null);
  const [error, setError] = useState<unknown>(null);
  const load = async () => {
    setError(null);
    const [roles, registry] = await Promise.all([fetchRoles(), fetchRegistry()]);
    if (roles.error || registry.error || !roles.data || !registry.data) return setError(roles.error ?? registry.error);
    setData({ roles: roles.data.filter((r) => !r.archived && !r.is_super_admin), permissions: registry.data.permissions });
  };
  useEffect(() => {
    void load();
  }, []);
  const latest = data ? newestRelease(data.permissions) : null;
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('newPermissions.title', { release: latest?.release ?? '' })} intro={t('newPermissions.intro')} testID="new-permissions">
        {error ? <ErrorState error={error} onRetry={() => void load()} /> : !data || !latest ? <Skeleton lines={4} /> :
          latest.permissions.length === 0 ? <EmptyState icon="done-all" title={t('newPermissions.none')} /> : (
            <View style={{ gap: space.sm }}>
              {latest.permissions.map((p) => {
                const given = data.roles.filter((r) => grantOf(r, p.key) !== null).map(roleName);
                return (
                  <View key={p.key} style={{ gap: space.xs, padding: space.md, borderRadius: 12, backgroundColor: colors.surfaceContainerLow }}
                    testID={`new-${p.key}`}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm, flexWrap: 'wrap' }}>
                      <AppText variant="label" style={{ flexShrink: 1 }}>{permissionLabel(p.key)}</AppText>
                      {p.sensitive ? <Badge label={t('role.sensitive')} tone="error" icon="shield" /> : null}
                    </View>
                    <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{permissionHelp(p.key)}</AppText>
                    <AppText variant="bodySmall">{given.length ? t('newPermissions.givenTo', { roles: given.join(', ') }) : t('newPermissions.givenToNone')}</AppText>
                  </View>
                );
              })}
            </View>
          )}
      </Screen>
    </View>
  );
}
