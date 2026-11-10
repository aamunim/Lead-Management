import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { PhoneInput } from '@/components/fields/inputs';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import {
  archiveBranch, branchUsage, createBranch, fetchBranchTree, fetchUsers, moveBranchContents, updateBranch,
  type BranchUnit, type BranchUsage, type UserListItem,
} from '@/lib/admin';
import { useFormat } from '@/lib/locale';
import { useSetting } from '@/lib/settings';
import { Badge, Row, SelectField } from '@/ui/admin/parts';
import { BottomSheet, Button, EmptyState, ErrorState, Screen, Skeleton, TextField, useConfirm, useSnackbar } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Settings → Branches (0A.19-T1/T2, Ch 12.2): list, add, edit (name, address, phone, head), archive. A branch still
// in use is archived only after everything is moved to another branch (one call, audited). Hidden when branches are off.
const NONE = '__none__';
type Editing = { mode: 'new' } | { mode: 'edit'; branch: BranchUnit };

export default function BranchesScreen() {
  const { t } = useTranslation('admin');
  const { colors, space } = useTheme();
  const branchesOn = useSetting<boolean>('branches_enabled', false) === true;
  const [branches, setBranches] = useState<BranchUnit[] | null>(null);
  const [people, setPeople] = useState<UserListItem[]>([]);
  const [error, setError] = useState<unknown>(null);
  const [editing, setEditing] = useState<Editing | null>(null);

  const load = useCallback(async () => {
    setError(null);
    const [tree, users] = await Promise.all([fetchBranchTree(), fetchUsers('active', '')]);
    if (tree.error || !tree.data) return setError(tree.error);
    setBranches(tree.data.units.filter((u) => u.kind === 'branch'));
    setPeople(users.data?.items ?? []);
  }, []);
  useEffect(() => {
    if (branchesOn) void load();
  }, [branchesOn, load]);

  const active = (branches ?? []).filter((b) => !b.archived);
  const archived = (branches ?? []).filter((b) => b.archived);
  const nameOf = (id: string | null | undefined) => people.find((p) => p.user_id === id)?.display_name ?? '';

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('branches.title')} intro={branchesOn ? t('branches.intro') : undefined} testID="branches">
        {!branchesOn ? <EmptyState icon="store" title={t('branches.off')} body={t('branches.offBody')} testID="branches-off" />
          : error ? <ErrorState error={error} onRetry={() => void load()} testID="branches-error" />
            : !branches ? <Skeleton lines={3} testID="branches-loading" /> : (
              <>
                <Button icon="add" label={t('branches.add')} onPress={() => setEditing({ mode: 'new' })} testID="branches-add" />
                {active.length === 0 ? <EmptyState icon="store" title={t('branches.empty')} body={t('branches.emptyBody')} testID="branches-empty" /> : (
                  <View style={{ gap: space.sm }}>
                    {active.map((b) => (
                      <Row key={b.id} icon="store" title={b.name} testID={`branch-${b.name}`} onPress={() => setEditing({ mode: 'edit', branch: b })}
                        subtitle={[b.branch?.address, b.branch?.phone, b.branch?.head_user_id ? t('branches.headLine', { name: nameOf(b.branch.head_user_id) }) : null]
                          .filter(Boolean).join(' · ')} />
                    ))}
                  </View>
                )}
                {archived.length > 0 ? (
                  <View style={{ gap: space.sm }}>
                    <AppText variant="titleSmall">{t('branches.archived')}</AppText>
                    {archived.map((b) => <Row key={b.id} icon="inventory-2" title={b.name} badge={<Badge label={t('branches.archived')} />} testID={`branch-archived-${b.name}`} />)}
                  </View>
                ) : null}
              </>
            )}
      </Screen>
      {editing ? (
        <BranchSheet editing={editing} people={people} others={active.filter((b) => editing.mode === 'new' || b.id !== editing.branch.id)}
          onClose={() => setEditing(null)} onDone={() => { setEditing(null); void load(); }} />
      ) : null}
    </View>
  );
}

function BranchSheet({ editing, people, others, onClose, onDone }: {
  editing: Editing; people: UserListItem[]; others: BranchUnit[]; onClose: () => void; onDone: () => void;
}) {
  const { t } = useTranslation('admin');
  const { colors, space } = useTheme();
  const format = useFormat();
  const errorText = useErrorText();
  const snackbar = useSnackbar();
  const confirm = useConfirm();
  const current = editing.mode === 'edit' ? editing.branch : null;
  const [name, setName] = useState(current?.name ?? '');
  const [address, setAddress] = useState(current?.branch?.address ?? '');
  const [phone, setPhone] = useState<string | null>(current?.branch?.phone ?? null);
  const [head, setHead] = useState<string>(current?.branch?.head_user_id ?? NONE);
  const [error, setError] = useState<{ field: 'name' | 'phone' | 'form'; text: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [usage, setUsage] = useState<BranchUsage | null>(null);
  const [moveTo, setMoveTo] = useState<string | null>(null);

  const save = async () => {
    if (!name.trim()) return setError({ field: 'name', text: t('branches.nameRequired') });
    setBusy(true);
    const input = { name: name.trim(), address, phone, headUserId: head === NONE ? null : head };
    const r = current ? await updateBranch(current.id, input) : await createBranch(input);
    setBusy(false);
    if (r.error) return setError({ field: r.error.code === 'phone_invalid' ? 'phone' : 'form', text: errorText(r.error).message });
    snackbar.show({ text: current ? t('branches.saved') : t('branches.created') });
    onDone();
  };

  const archive = async () => {
    if (!current) return;
    setBusy(true);
    const u = await branchUsage(current.id);
    setBusy(false);
    if (u.error || !u.data) return setError({ field: 'form', text: u.error ? errorText(u.error).message : '' });
    if (u.data.total > 0) return setUsage(u.data);
    if (!(await confirm({ title: t('branches.archiveTitle', { name: current.name }), message: t('branches.archiveBody'),
      confirmLabel: t('branches.archive'), danger: true }))) return;
    await doArchive();
  };
  const doArchive = async () => {
    if (!current) return;
    setBusy(true);
    const r = await archiveBranch(current.id);
    setBusy(false);
    if (r.error) return setError({ field: 'form', text: errorText(r.error).message });
    snackbar.show({ text: t('branches.archivedDone') });
    onDone();
  };
  const moveAndArchive = async () => {
    if (!current || !moveTo) return;
    setBusy(true);
    const m = await moveBranchContents(current.id, moveTo);
    setBusy(false);
    if (m.error) return setError({ field: 'form', text: errorText(m.error).message });
    await doArchive();
  };

  if (usage && current) {
    return (
      <BottomSheet visible onClose={onClose} title={t('branches.moveTitle', { name: current.name })} testID="branch-move"
        footer={<Button variant="danger" label={t('branches.moveAndArchive')} loading={busy} disabled={!moveTo} fullWidth
          onPress={() => void moveAndArchive()} testID="branch-move-confirm" />}>
        <AppText>{t('branches.moveBody')}</AppText>
        <View style={{ gap: space.xs }} testID="branch-usage">
          {(['units', 'unit_members', 'managers', 'staff_home_branch', 'role_assignments'] as const).filter((k) => usage[k] > 0).map((k) => (
            <AppText key={k} variant="bodySmall">{t(`branches.usage.${k}`, { n: format.number(usage[k]) })}</AppText>
          ))}
        </View>
        <SelectField label={t('branches.moveTo')} value={moveTo} onChange={setMoveTo} testID="branch-move-to"
          choices={others.map((b) => ({ value: b.id, label: b.name, testID: `branch-move-to-${b.name}` }))} />
        {error ? <AppText style={{ color: colors.error }} accessibilityRole="alert">{error.text}</AppText> : null}
      </BottomSheet>
    );
  }

  return (
    <BottomSheet visible onClose={onClose} title={current ? t('branches.edit') : t('branches.add')} testID="branch-sheet"
      footer={<Button label={t('branches.save')} loading={busy} fullWidth onPress={() => void save()} testID="branch-save" />}>
      <TextField label={t('branches.name')} kind="name" required value={name} onChangeText={setName} maxLength={80}
        error={error?.field === 'name' ? error.text : null} testID="branch-name" />
      <TextField label={t('branches.address')} kind="multiline" value={address} onChangeText={setAddress} maxLength={300} testID="branch-address" />
      <PhoneInput label={t('branches.phone')} value={phone} onChange={setPhone} errorText={error?.field === 'phone' ? error.text : undefined} testID="branch-phone" />
      <SelectField label={t('branches.head')} value={head} onChange={setHead} testID="branch-head"
        choices={[{ value: NONE, label: t('branches.noHead') }, ...people.map((p) => ({ value: p.user_id, label: p.display_name ?? p.email ?? '' }))]} />
      {error?.field === 'form' ? <AppText style={{ color: colors.error }} accessibilityRole="alert" testID="branch-error">{error.text}</AppText> : null}
      {current ? <Button variant="outlined" icon="inventory-2" label={t('branches.archive')} loading={busy} onPress={() => void archive()} testID="branch-archive" /> : null}
    </BottomSheet>
  );
}
