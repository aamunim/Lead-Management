import { useEffect, useMemo, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { fetchRegistry, fetchRoles } from '@/lib/admin';
import { compareRoles, type Grant, type PermissionInfo, type RoleInfo } from '@/lib/admin-core';
import { Badge, SelectField, permissionLabel, roleName, tDynamic } from '@/ui/admin/parts';
import { ErrorState, Screen, Skeleton } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Compare two roles (0A.18-T5): permission by permission, differences first.
export default function RoleCompareScreen() {
  const { t } = useTranslation('admin');
  const { colors, space } = useTheme();
  const [data, setData] = useState<{ roles: RoleInfo[]; permissions: PermissionInfo[] } | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [a, setA] = useState<string | null>(null);
  const [b, setB] = useState<string | null>(null);

  const load = async () => {
    setError(null);
    const [roles, registry] = await Promise.all([fetchRoles(), fetchRegistry()]);
    if (roles.error || registry.error || !roles.data || !registry.data) return setError(roles.error ?? registry.error);
    setData({ roles: roles.data.filter((r) => !r.archived), permissions: registry.data.permissions });
  };
  useEffect(() => {
    void load();
  }, []);

  const roleA = data?.roles.find((r) => r.id === a);
  const roleB = data?.roles.find((r) => r.id === b);
  const rows = useMemo(() => (roleA && roleB && data ? compareRoles(roleA, roleB, data.permissions) : []), [roleA, roleB, data]);
  const show = (g: Grant | null) => (g === null ? t('compare.none') : g === true ? t('compare.given') : tDynamic(`admin:scopes.${g}`));
  const choices = (data?.roles ?? []).map((r) => ({ value: r.id, label: roleName(r) }));

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('compare.title')} testID="compare">
        {error ? <ErrorState error={error} onRetry={() => void load()} testID="compare-error" /> : !data ? <Skeleton lines={4} /> : (
          <>
            <SelectField label={t('compare.first')} value={a} onChange={setA} choices={choices} testID="compare-a" />
            <SelectField label={t('compare.second')} value={b} onChange={setB} choices={choices} testID="compare-b" />
            {!roleA || !roleB ? <AppText style={{ color: colors.onSurfaceVariant }}>{t('compare.pickBoth')}</AppText> : (
              <View style={{ gap: space.sm }} testID="compare-rows">
                {rows.every((r) => r.same) ? <AppText testID="compare-same">{t('compare.noDifference')}</AppText> : null}
                {rows.map((r) => (
                  <View key={r.key} style={{ gap: space.xs, padding: space.md, borderRadius: 12,
                    backgroundColor: r.same ? colors.surfaceContainerLow : colors.surfaceContainerHigh }} testID={`compare-${r.key}`}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm, flexWrap: 'wrap' }}>
                      <AppText variant="label" style={{ flex: 1, minWidth: 140 }}>{permissionLabel(r.key)}</AppText>
                      <Badge label={r.same ? t('compare.same') : t('compare.different')} tone={r.same ? 'neutral' : 'warning'} />
                    </View>
                    <AppText variant="bodySmall">{`${roleName(roleA)}: ${show(r.a)}`}</AppText>
                    <AppText variant="bodySmall">{`${roleName(roleB)}: ${show(r.b)}`}</AppText>
                  </View>
                ))}
              </View>
            )}
          </>
        )}
      </Screen>
    </View>
  );
}
