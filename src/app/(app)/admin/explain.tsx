import { useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import {
  explainAccess, fetchOrgTree, fetchRecordEntities, fetchRegistry, fetchUsers,
  type ExplainResult, type OrgUnit, type RecordRef, type UserListItem,
} from '@/lib/admin';
import type { PermissionInfo } from '@/lib/admin-core';
import { useFormat } from '@/lib/locale';
import { Badge, SelectField, permissionLabel, roleName, tDynamic } from '@/ui/admin/parts';
import { Button, ErrorState, Screen, Skeleton, TextField } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Basic access explainer (0A.18-T6, R16, Ch 11.14): pick a person and a record (a registered record type by number,
// or a described record) and see, role by role, what allows or blocks it — scope, branch / offering limit, dates.
const DESCRIBED = '__described__';
const NOBODY = '__nobody__';

type Data = { users: UserListItem[]; permissions: PermissionInfo[]; branches: OrgUnit[]; entities: { entity: string; permission: string; label_key: string }[] };

export default function ExplainScreen() {
  const params = useLocalSearchParams<{ user?: string }>();
  const { t } = useTranslation('admin');
  const { colors, space } = useTheme();
  const format = useFormat();
  const [data, setData] = useState<Data | null>(null);
  const [loadError, setLoadError] = useState<unknown>(null);
  const [userId, setUserId] = useState<string | null>(params.user ?? null);
  const [mode, setMode] = useState<string>(DESCRIBED);
  const [recordId, setRecordId] = useState('');
  const [permission, setPermission] = useState<string | null>(null);
  const [owner, setOwner] = useState<string>(NOBODY);
  const [creator, setCreator] = useState<string>(NOBODY);
  const [branch, setBranch] = useState<string>(NOBODY);
  const [result, setResult] = useState<ExplainResult | null>(null);
  const [checkError, setCheckError] = useState<unknown>(null);
  const [checking, setChecking] = useState(false);

  const load = async () => {
    setLoadError(null);
    const [users, registry, tree, entities] = await Promise.all([fetchUsers(null, ''), fetchRegistry(), fetchOrgTree(), fetchRecordEntities()]);
    const error = users.error ?? registry.error ?? tree.error ?? entities.error;
    if (error || !users.data || !registry.data || !tree.data) return setLoadError(error);
    setData({ users: users.data.items, permissions: registry.data.permissions.filter((p) => p.key !== '*'),
      branches: tree.data.branches_enabled ? tree.data.units.filter((u) => u.kind === 'branch' && !u.archived) : [], entities: entities.data ?? [] });
  };
  useEffect(() => {
    void load();
  }, []);

  const check = async () => {
    if (!userId) return;
    const ref: RecordRef = mode === DESCRIBED
      ? { permission: permission ?? '', owner_id: owner === NOBODY ? null : owner, created_by: creator === NOBODY ? null : creator,
        branch_id: branch === NOBODY ? null : branch }
      : { entity: mode, id: recordId.trim() };
    setChecking(true);
    setCheckError(null);
    setResult(null);
    const r = await explainAccess(userId, ref);
    setChecking(false);
    if (r.error) setCheckError(r.error);
    else setResult(r.data);
  };

  const people = (data?.users ?? []).map((u) => ({ value: u.user_id, label: u.display_name ?? u.email ?? '', testID: `explain-person-${u.display_name ?? u.user_id}` }));
  const nameOf = (id: string | null) => data?.users.find((u) => u.user_id === id)?.display_name ?? '';
  const branchName = (id: string) => data?.branches.find((b) => b.id === id)?.name ?? '';
  const ready = !!userId && (mode === DESCRIBED ? !!permission : recordId.trim().length > 0);

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('explain.title')} intro={t('explain.intro')} testID="explain">
        {loadError ? <ErrorState error={loadError} onRetry={() => void load()} testID="explain-error" /> : !data ? <Skeleton lines={4} /> : (
          <>
            <SelectField label={t('explain.person')} value={userId} onChange={setUserId} placeholder={t('explain.pickPerson')} choices={people}
              testID="explain-person" />
            <SelectField label={t('explain.recordType')} value={mode} onChange={setMode} testID="explain-type"
              help={data.entities.length === 0 ? t('explain.noRecordTypes') : undefined}
              choices={[{ value: DESCRIBED, label: t('explain.described') },
                ...data.entities.map((e) => ({ value: e.entity, label: tDynamic(e.label_key, { defaultValue: e.entity }) }))]} />
            {mode === DESCRIBED ? (
              <>
                <SelectField label={t('explain.permission')} value={permission} onChange={setPermission} testID="explain-permission"
                  choices={data.permissions.map((p) => ({ value: p.key, label: permissionLabel(p.key), testID: `explain-permission-${p.key}` }))} />
                <SelectField label={t('explain.owner')} value={owner} onChange={setOwner} testID="explain-owner"
                  choices={[{ value: NOBODY, label: t('explain.nobody') }, ...people.map((p) => ({ ...p, testID: `explain-owner-${p.label}` }))]} />
                <SelectField label={t('explain.creator')} value={creator} onChange={setCreator} testID="explain-creator"
                  choices={[{ value: NOBODY, label: t('explain.nobody') }, ...people.map((p) => ({ ...p, testID: `explain-creator-${p.label}` }))]} />
                {data.branches.length > 0 ? (
                  <SelectField label={t('explain.branch')} value={branch} onChange={setBranch} testID="explain-branch"
                    choices={[{ value: NOBODY, label: t('explain.noBranch') },
                      ...data.branches.map((b) => ({ value: b.id, label: b.name, testID: `explain-branch-${b.name}` }))]} />
                ) : null}
              </>
            ) : (
              <TextField label={t('explain.recordId')} kind="search" value={recordId} onChangeText={setRecordId} testID="explain-record-id" />
            )}
            <Button icon="search" label={t('explain.check')} onPress={() => void check()} loading={checking} disabled={!ready} testID="explain-check" />

            {checkError ? <ErrorState error={checkError} onRetry={() => void check()} testID="explain-check-error" /> : null}
            {result ? (
              <View style={{ gap: space.md }} testID="explain-result">
                <View style={{ gap: space.xs, padding: space.md, borderRadius: 12,
                  backgroundColor: result.allowed ? colors.successContainer : colors.errorContainer }}>
                  <AppText variant="title" style={{ color: result.allowed ? colors.onSuccessContainer : colors.onErrorContainer }}
                    testID="explain-verdict" accessibilityLiveRegion="polite">
                    {result.allowed ? t('explain.allowed', { name: nameOf(userId) }) : t('explain.blocked', { name: nameOf(userId) })}
                  </AppText>
                  <AppText style={{ color: result.allowed ? colors.onSuccessContainer : colors.onErrorContainer }} testID="explain-summary">
                    {`${permissionLabel(result.permission)} · ${t(`explain.summary.${result.summary}`)}`}
                  </AppText>
                </View>
                {result.reasons.map((r) => (
                  <View key={r.assignment_id} style={{ gap: space.xs, padding: space.md, borderRadius: 12, backgroundColor: colors.surfaceContainerLow }}
                    testID={`explain-reason-${roleName(r)}`}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm, flexWrap: 'wrap' }}>
                      <AppText variant="label" style={{ flex: 1, minWidth: 120 }}>{roleName(r)}</AppText>
                      <Badge label={t(`explain.verdict.${r.verdict}`)} tone={r.verdict === 'allows' ? 'success' : r.verdict === 'blocks' ? 'error' : 'neutral'}
                        icon={r.verdict === 'allows' ? 'check' : r.verdict === 'blocks' ? 'block' : 'remove'} />
                    </View>
                    <AppText variant="bodySmall" testID={`explain-reason-${roleName(r)}-rule`}>
                      {tDynamic(`admin:explain.rules.${r.rule}`, {
                        date: r.rule === 'not_started' ? format.dateTime(r.valid_from) : r.valid_to ? format.dateTime(r.valid_to) : '',
                        scope: r.scope ? tDynamic(`admin:scopes.${r.scope}`) : '',
                      })}
                    </AppText>
                    <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>
                      {[r.scope ? `${t('role.scope')}: ${tDynamic(`admin:scopes.${r.scope}`)}` : null,
                        r.branch_id && data.branches.length > 0 ? t('user.inBranch', { branch: branchName(r.branch_id) }) : null,
                        r.valid_to ? t('user.until', { date: format.dateTime(r.valid_to) }) : null].filter(Boolean).join(' · ')}
                    </AppText>
                  </View>
                ))}
              </View>
            ) : null}
          </>
        )}
      </Screen>
    </View>
  );
}
