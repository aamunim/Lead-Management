import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { DateTimeField } from '@/components/fields/pickers';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { assignRole, fetchOrgTree, fetchRoles, fetchUser, previewAssignment, type AssignmentPreview, type OrgTree } from '@/lib/admin';
import type { RoleInfo } from '@/lib/admin-core';
import { Badge, SelectField, permissionLabel, roleName, tDynamic } from '@/ui/admin/parts';
import { Button, ErrorState, FormScreen, Skeleton, useSnackbar, useSubmit } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Give a role (0A.18-T3, Ch 11.16 #2): role + where (branch or unit) + validity dates, with the "resulting access"
// preview before saving. The offering limit is shown but waits for offerings (1A). The server re-checks everything:
// no escalation, outranking, last Super Admin.
const WHOLE = '__whole__';
const NONE = '__none__';

export default function AssignScreen() {
  const { user: userId } = useLocalSearchParams<{ user: string }>();
  const { t } = useTranslation('admin');
  const { colors, space } = useTheme();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [data, setData] = useState<{ roles: RoleInfo[]; tree: OrgTree; name: string } | null>(null);
  const [loadError, setLoadError] = useState<unknown>(null);
  const [roleId, setRoleId] = useState<string | null>(null);
  const [branch, setBranch] = useState<string>(WHOLE);
  const [unit, setUnit] = useState<string>(NONE);
  const [validFrom, setValidFrom] = useState<string | null>(null);
  const [validTo, setValidTo] = useState<string | null>(null);
  const [preview, setPreview] = useState<AssignmentPreview | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const load = async () => {
    setLoadError(null);
    const [roles, tree, user] = await Promise.all([fetchRoles(), fetchOrgTree(), fetchUser(userId)]);
    const error = roles.error ?? tree.error ?? user.error;
    if (error || !roles.data || !tree.data || !user.data) return setLoadError(error);
    setData({ roles: roles.data.filter((r) => !r.archived), tree: tree.data, name: user.data.display_name ?? user.data.email ?? '' });
  };
  useEffect(() => {
    void load();
    // load once per person
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId]);

  const branchId = branch === WHOLE ? null : branch;
  const unitId = unit === NONE ? null : unit;
  useEffect(() => {
    let alive = true;
    setPreview(null);
    if (!roleId) return undefined;
    void previewAssignment({ userId, roleId, branchId, orgUnitId: unitId }).then(({ data: p }) => {
      if (alive) setPreview(p);
    });
    return () => {
      alive = false;
    };
  }, [userId, roleId, branchId, unitId]);

  const { submit, submitting } = useSubmit(async () => {
    if (!roleId) return setFormError(t('assign.pickRoleFirst'));
    setFormError(null);
    const { error } = await assignRole({ userId, roleId, orgUnitId: unitId, branchId, validFrom, validTo, offeringLimit: null });
    if (error) return setFormError(errorText(error).message);
    snackbar.show({ text: t('assign.saved') });
    setSaved(true);
  });
  // Leave only after the saved state rendered, so "discard changes?" does not ask about what was just saved.
  useEffect(() => {
    if (saved) router.back();
  }, [saved]);

  const units = useMemo(() => (data?.tree.units ?? []).filter((u) => !u.archived), [data]);
  const branches = units.filter((u) => u.kind === 'branch');
  const otherUnits = units.filter((u) => u.kind !== 'branch');

  if (!data) {
    return (
      <View style={{ flex: 1, backgroundColor: colors.background }}>
        <AppHeader back />
        <View style={{ padding: space.lg }}>
          {loadError ? <ErrorState error={loadError} onRetry={() => void load()} testID="assign-error" /> : <Skeleton lines={4} testID="assign-loading" />}
        </View>
      </View>
    );
  }

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <FormScreen title={t('assign.title')} notice={t('assign.for', { name: data.name })} onSave={() => void submit()} saving={submitting}
        dirty={!!roleId && !saved} saveLabel={t('assign.save')} testID="assign">
        <SelectField label={t('assign.role')} value={roleId} placeholder={t('assign.pickRole')} onChange={setRoleId} testID="assign-role"
          choices={data.roles.map((r) => ({ value: r.id, label: roleName(r), testID: `assign-role-${roleName(r)}` }))} />
        {data.tree.branches_enabled && branches.length > 0 ? (
          <SelectField label={t('assign.where')} value={branch} onChange={setBranch} testID="assign-branch"
            choices={[{ value: WHOLE, label: t('assign.wholeInstitution'), testID: 'assign-branch-whole' },
              ...branches.map((b) => ({ value: b.id, label: b.name, testID: `assign-branch-${b.name}` }))]} />
        ) : null}
        {otherUnits.length > 0 ? (
          <SelectField label={t('assign.unit')} value={unit} onChange={setUnit} testID="assign-unit"
            choices={[{ value: NONE, label: t('assign.noUnit') }, ...otherUnits.map((u) => ({ value: u.id, label: u.name, testID: `assign-unit-${u.name}` }))]} />
        ) : null}
        <DateTimeField label={t('assign.validFrom')} value={validFrom} onChange={setValidFrom} testID="assign-from" />
        <View style={{ gap: space.xs }}>
          <DateTimeField label={t('assign.validTo')} value={validTo} onChange={setValidTo} testID="assign-to" />
          {validTo ? <Button variant="text" label={t('assign.clearEnd')} onPress={() => setValidTo(null)} testID="assign-to-clear" /> : null}
        </View>
        <View style={{ gap: space.xs }}>
          <AppText variant="label">{t('assign.offerings')}</AppText>
          <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{t('assign.offeringsLater')}</AppText>
        </View>

        <View style={{ gap: space.sm, padding: space.md, borderRadius: 12, backgroundColor: colors.surfaceContainerLow }} testID="assign-preview">
          <AppText variant="titleSmall">{t('assign.preview')}</AppText>
          <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{t('assign.previewHelp')}</AppText>
          {!roleId ? <AppText style={{ color: colors.onSurfaceVariant }}>{t('assign.pickRoleFirst')}</AppText>
            : !preview ? <Skeleton lines={2} />
              : preview.adds.length === 0 ? <AppText>{t('assign.previewEmpty')}</AppText>
                : preview.adds.map((row) => (
                  <View key={row.permission} style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm, flexWrap: 'wrap' }}>
                    <AppText variant="bodySmall" style={{ flex: 1, minWidth: 160 }}>
                      {`${permissionLabel(row.permission)} · ${tDynamic(`admin:scopes.${row.scope ?? 'all'}`)}${
                        branchId ? ` · ${branches.find((b) => b.id === branchId)?.name ?? ''}` : ''}`}
                    </AppText>
                    {row.sensitive ? <Badge label={t('role.sensitive')} tone="error" icon="shield" /> : null}
                  </View>
                ))}
        </View>
        {formError ? <AppText style={{ color: colors.error }} accessibilityRole="alert" testID="assign-form-error">{formError}</AppText> : null}
      </FormScreen>
    </View>
  );
}
