import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { createRole, fetchRoles } from '@/lib/admin';
import type { RoleInfo } from '@/lib/admin-core';
import { useFormat } from '@/lib/locale';
import { Badge, Row, SelectField, roleName } from '@/ui/admin/parts';
import { BottomSheet, Button, EmptyState, ErrorState, Screen, Skeleton, TextField, useSnackbar } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Settings → Roles (0A.18-T4/T5): built-in roles from the template and the institution's own roles; create a role
// from a template role (D26), compare two roles, see the new permissions of this release (R20).
const BLANK = '__blank__';

export default function RolesScreen() {
  const { t } = useTranslation('admin');
  const { colors, space } = useTheme();
  const format = useFormat();
  const [roles, setRoles] = useState<RoleInfo[] | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [creating, setCreating] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    const result = await fetchRoles();
    if (result.error || !result.data) return setError(result.error);
    setRoles(result.data);
  }, []);
  useFocusEffect(useCallback(() => {
    void load();
  }, [load]));

  const active = (roles ?? []).filter((r) => !r.archived);
  const archived = (roles ?? []).filter((r) => r.archived);
  const subtitle = (r: RoleInfo) => [r.is_system ? t('roles.builtIn') : t('roles.custom'),
    r.is_super_admin ? t('roles.superAdmin') : t('roles.permissionCount', { count: Object.keys(r.grants).length, n: format.number(Object.keys(r.grants).length) })]
    .join(' · ');

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('roles.title')} intro={t('roles.intro')} testID="roles">
        <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
          <Button icon="add" label={t('roles.newRole')} onPress={() => setCreating(true)} disabled={!roles} testID="roles-new" />
          <Button variant="tonal" icon="compare-arrows" label={t('roles.compare')} onPress={() => router.push('/admin/role-compare')} testID="roles-compare" />
          <Button variant="tonal" icon="fiber-new" label={t('roles.newPermissions')} onPress={() => router.push('/admin/new-permissions')}
            testID="roles-new-permissions" />
        </View>
        {error ? <ErrorState error={error} onRetry={() => void load()} testID="roles-error" />
          : !roles ? <Skeleton lines={5} testID="roles-loading" />
            : active.length === 0 ? <EmptyState icon="admin-panel-settings" title={t('roles.empty')} testID="roles-empty" />
              : (
                <View style={{ gap: space.sm }}>
                  {active.map((r) => (
                    <Row key={r.id} title={roleName(r)} subtitle={subtitle(r)} icon={r.is_super_admin ? 'verified-user' : 'badge'}
                      onPress={() => router.push({ pathname: '/admin/role/[id]', params: { id: r.id } })} testID={`role-${roleName(r)}`} />
                  ))}
                </View>
              )}
        {archived.length > 0 ? (
          <View style={{ gap: space.sm }}>
            <AppText variant="titleSmall">{t('roles.archived')}</AppText>
            {archived.map((r) => <Row key={r.id} title={roleName(r)} badge={<Badge label={t('roles.archived')} />} />)}
          </View>
        ) : null}
      </Screen>
      {creating && roles ? <NewRoleSheet roles={active} onClose={() => setCreating(false)} /> : null}
    </View>
  );
}

function NewRoleSheet({ roles, onClose }: { roles: RoleInfo[]; onClose: () => void }) {
  const { t } = useTranslation('admin');
  const errorText = useErrorText();
  const snackbar = useSnackbar();
  const [name, setName] = useState('');
  const [from, setFrom] = useState<string>(BLANK);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const save = async () => {
    if (!name.trim()) return setError(t('role.name'));
    setSaving(true);
    const parent = roles.find((r) => r.id === from);
    const result = await createRole(name.trim(), parent?.id ?? null, parent?.flags ?? []);
    setSaving(false);
    if (result.error || !result.data) return setError(result.error ? errorText(result.error).message : null);
    snackbar.show({ text: t('roles.created') });
    onClose();
    router.push({ pathname: '/admin/role/[id]', params: { id: result.data } });
  };
  return (
    <BottomSheet visible onClose={onClose} title={t('roles.newTitle')} testID="new-role"
      footer={<Button label={t('roles.create')} loading={saving} fullWidth onPress={() => void save()} testID="new-role-save" />}>
      <SelectField label={t('roles.startFrom')} value={from} onChange={setFrom} testID="new-role-from"
        choices={[{ value: BLANK, label: t('roles.blank'), testID: 'new-role-from-blank' },
          ...roles.filter((r) => !r.is_super_admin).map((r) => ({ value: r.id, label: roleName(r), testID: `new-role-from-${roleName(r)}` }))]} />
      <TextField label={t('roles.name')} kind="text" required value={name} onChangeText={setName} maxLength={60} error={error}
        last onDone={() => void save()} testID="new-role-name" />
    </BottomSheet>
  );
}
