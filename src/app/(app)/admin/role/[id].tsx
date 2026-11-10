import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { copyRole, deleteRole, fetchRegistry, fetchRoles, setRoleGrants, updateRole } from '@/lib/admin';
import {
  SCOPES, changedKeys, groupByModule, setGrant, touchesSensitive, type Grants, type PermissionInfo, type RoleInfo, type Scope,
} from '@/lib/admin-core';
import { Badge, CheckRow, Chips, SelectField, permissionHelp, permissionLabel, roleName, tDynamic } from '@/ui/admin/parts';
import { BottomSheet, Button, ErrorState, FormScreen, Skeleton, TextField, useSnackbar, useSubmit } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Role editor (0A.18-T4, Ch 11.5 / 11.9 / 11.14): generated from the permission registry — module groups, label and
// help per permission, sensitive badge, scope for scopable permissions — plus behaviour flags, copy and delete
// (people move to another role first). Sensitive changes need two-step sign-in; the server enforces it.
type Data = { role: RoleInfo; roles: RoleInfo[]; permissions: PermissionInfo[]; flags: string[] };

export default function RoleScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t } = useTranslation('admin');
  const { t: tRoles } = useTranslation('roles');
  const { colors, space } = useTheme();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [data, setData] = useState<Data | null>(null);
  const [loadError, setLoadError] = useState<unknown>(null);
  const [name, setName] = useState('');
  const [flags, setFlags] = useState<string[]>([]);
  const [grants, setGrants] = useState<Grants>({});
  const [formError, setFormError] = useState<string | null>(null);
  const [copying, setCopying] = useState(false);
  const [deleting, setDeleting] = useState(false);

  const load = useCallback(async () => {
    setLoadError(null);
    const [roles, registry] = await Promise.all([fetchRoles(), fetchRegistry()]);
    const error = roles.error ?? registry.error;
    const role = roles.data?.find((r) => r.id === id);
    if (error || !roles.data || !registry.data || !role) return setLoadError(error ?? { code: 'role_unknown' });
    setData({ role, roles: roles.data, ...registry.data });
    setName(role.name ?? '');
    setFlags(role.flags);
    setGrants(role.grants);
  }, [id]);
  useEffect(() => {
    void load();
  }, [load]);

  const groups = useMemo(() => groupByModule(data?.permissions ?? []), [data]);
  const flagKeys = (r: RoleInfo) => [...r.flags].sort().join(',');
  const dirty = !!data && ((name.trim() || null) !== (data.role.name ?? null) || [...flags].sort().join(',') !== flagKeys(data.role)
    || changedKeys(data.role.grants, grants).length > 0);
  const sensitiveChange = !!data && touchesSensitive(data.role.grants, grants, data.permissions);
  const locked = !!data && (data.role.is_super_admin || data.role.archived);

  const { submit, submitting } = useSubmit(async () => {
    if (!data || locked) return;
    setFormError(null);
    if ((name.trim() || null) !== (data.role.name ?? null) || [...flags].sort().join(',') !== flagKeys(data.role)) {
      const r = await updateRole(data.role.id, name.trim() || null, flags);
      if (r.error) return setFormError(errorText(r.error).message);
    }
    if (changedKeys(data.role.grants, grants).length > 0) {
      const r = await setRoleGrants(data.role.id, grants);
      if (r.error) return setFormError(errorText(r.error).message);
    }
    snackbar.show({ text: t('role.saved') });
    await load();
  });

  if (!data) {
    return (
      <View style={{ flex: 1, backgroundColor: colors.background }}>
        <AppHeader back />
        <View style={{ padding: space.lg }}>
          {loadError ? <ErrorState error={loadError} onRetry={() => void load()} testID="role-error" /> : <Skeleton lines={6} testID="role-loading" />}
        </View>
      </View>
    );
  }

  const { role } = data;
  const toggle = (p: PermissionInfo) => setGrants((g) => setGrant(g, p, g[p.key] === undefined ? true : null));
  const scopeChoices = (key: string) => SCOPES.map((s) => ({ value: s, label: t(`scopes.${s}`), testID: `grant-${key}-scope-${s}` }));

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <FormScreen title={roleName(role)} onSave={() => void submit()} saving={submitting} dirty={dirty && !locked} saveLabel={t('role.save')}
        notice={role.is_super_admin ? t('role.superAdmin') : role.archived ? t('role.archived') : null} testID="role">
        {!role.is_super_admin ? (
          <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
            <Button variant="tonal" icon="content-copy" label={t('role.copy')} onPress={() => setCopying(true)} testID="role-copy" />
            {!role.is_system && !role.archived ? (
              <Button variant="outlined" icon="delete-outline" label={t('role.delete')} onPress={() => setDeleting(true)} testID="role-delete" />
            ) : null}
          </View>
        ) : null}

        {!locked ? (
          <>
            <TextField label={t('role.name')} kind="text" value={name} onChangeText={setName} maxLength={60} required={!role.is_system}
              help={role.is_system ? t('role.nameHelp') : undefined} testID="role-name" />

            <View style={{ gap: space.xs }} testID="role-flags">
              <AppText variant="titleSmall" accessibilityRole="header">{t('role.flags')}</AppText>
              <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{t('role.flagsHelp')}</AppText>
              {data.flags.map((f) => (
                <CheckRow key={f} label={tRoles(`flags.${f}` as 'flags.assignable')} checked={flags.includes(f)} testID={`flag-${f}`}
                  onToggle={() => setFlags((cur) => (cur.includes(f) ? cur.filter((x) => x !== f) : [...cur, f]))} />
              ))}
            </View>

            <View style={{ gap: space.md }} testID="role-permissions">
              <AppText variant="titleSmall" accessibilityRole="header">{t('role.permissions')}</AppText>
              {groups.map((g) => (
                <View key={g.module} style={{ gap: space.xs, padding: space.md, borderRadius: 12, backgroundColor: colors.surfaceContainerLow }}>
                  <AppText variant="label">{tDynamic(`admin:modules.${g.module}`, { defaultValue: g.module })}</AppText>
                  {g.permissions.map((p) => {
                    const on = grants[p.key] !== undefined;
                    return (
                      <View key={p.key} style={{ gap: space.xs }}>
                        <CheckRow label={permissionLabel(p.key)} help={permissionHelp(p.key)} checked={on} onToggle={() => toggle(p)}
                          badge={p.sensitive ? <Badge label={t('role.sensitive')} tone="error" icon="shield" /> : null} testID={`grant-${p.key}`} />
                        {on && p.scopable ? (
                          <View style={{ paddingLeft: 40, gap: space.xs }}>
                            <AppText variant="caption">{t('role.scope')}</AppText>
                            <Chips label={t('role.scope')} selected={grants[p.key] as Scope} choices={scopeChoices(p.key)}
                              onSelect={(s) => setGrants((cur) => setGrant(cur, p, s))} />
                            <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{t(`scopes.help.${grants[p.key] as Scope}`)}</AppText>
                          </View>
                        ) : null}
                      </View>
                    );
                  })}
                </View>
              ))}
            </View>
            {sensitiveChange ? <AppText style={{ color: colors.onSurfaceVariant }} testID="role-sensitive-note">{t('role.sensitiveNote')}</AppText> : null}
          </>
        ) : null}
        {formError ? <AppText style={{ color: colors.error }} accessibilityRole="alert" testID="role-form-error">{formError}</AppText> : null}
      </FormScreen>
      {copying ? <CopySheet role={role} onClose={() => setCopying(false)} /> : null}
      {deleting ? <DeleteSheet role={role} roles={data.roles} onClose={() => setDeleting(false)} /> : null}
    </View>
  );
}

function CopySheet({ role, onClose }: { role: RoleInfo; onClose: () => void }) {
  const { t } = useTranslation('admin');
  const errorText = useErrorText();
  const snackbar = useSnackbar();
  const [name, setName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const save = async () => {
    if (!name.trim()) return setError(t('role.copyName'));
    setSaving(true);
    const r = await copyRole(role.id, name.trim());
    setSaving(false);
    if (r.error || !r.data) return setError(r.error ? errorText(r.error).message : null);
    snackbar.show({ text: t('role.copied') });
    onClose();
    router.replace({ pathname: '/admin/role/[id]', params: { id: r.data } });
  };
  return (
    <BottomSheet visible onClose={onClose} title={t('role.copyTitle', { name: roleName(role) })} testID="copy-role"
      footer={<Button label={t('role.copy')} loading={saving} fullWidth onPress={() => void save()} testID="copy-role-save" />}>
      <AppText>{t('role.copyNote')}</AppText>
      <TextField label={t('role.copyName')} kind="text" required value={name} onChangeText={setName} maxLength={60} error={error}
        last onDone={() => void save()} testID="copy-role-name" />
    </BottomSheet>
  );
}

function DeleteSheet({ role, roles, onClose }: { role: RoleInfo; roles: RoleInfo[]; onClose: () => void }) {
  const { t } = useTranslation('admin');
  const errorText = useErrorText();
  const snackbar = useSnackbar();
  const { colors } = useTheme();
  const others = roles.filter((r) => r.id !== role.id && !r.archived && !r.is_super_admin);
  const [moveTo, setMoveTo] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const run = async () => {
    setSaving(true);
    const r = await deleteRole(role.id, moveTo);
    setSaving(false);
    if (r.error) return setError(errorText(r.error).message);
    snackbar.show({ text: t('role.deleted') });
    onClose();
    router.back();
  };
  return (
    <BottomSheet visible onClose={onClose} title={t('role.deleteTitle', { name: roleName(role) })} testID="delete-role"
      footer={<Button variant="danger" label={t('role.delete')} loading={saving} fullWidth onPress={() => void run()} testID="delete-role-confirm" />}>
      <AppText>{t('role.deleteBody')}</AppText>
      <SelectField label={t('role.moveTo')} value={moveTo} onChange={setMoveTo} placeholder={t('pick.none')} testID="delete-role-move"
        choices={others.map((r) => ({ value: r.id, label: roleName(r) }))} />
      {error ? <AppText style={{ color: colors.error }} accessibilityRole="alert" testID="delete-role-error">{error}</AppText> : null}
    </BottomSheet>
  );
}
