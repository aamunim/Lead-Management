import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { PhoneInput } from '@/components/fields/inputs';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import {
  approveUser, deactivateUser, fetchOrgTree, fetchUser, reactivateUser, unassignRole, updateContact,
  type Assignment, type Result, type UserDetail,
} from '@/lib/admin';
import { describeError } from '@/lib/errors';
import { useFormat } from '@/lib/locale';
import { Badge, Row, Section, permissionLabel, roleName, tDynamic } from '@/ui/admin/parts';
import { BottomSheet, Button, ErrorState, Screen, Skeleton, TextField, useConfirm, useSnackbar } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Settings → Users → one person (0A.18-T1/T2, Ch 11.14): contact (email change applied at once), status actions with
// confirmation (deactivation ends their sessions at once), role assignments with limits and dates, units, the
// resulting access, and the actions that arrive later (password reset 0B, activity phase 4, hand-over 1B).
type Load = { status: 'loading' } | { status: 'error'; error: unknown } | { status: 'ready'; user: UserDetail; names: Record<string, string> };

export default function UserScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t } = useTranslation('admin');
  const { colors, space } = useTheme();
  const format = useFormat();
  const confirm = useConfirm();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [load, setLoad] = useState<Load>({ status: 'loading' });
  const [busy, setBusy] = useState(false);
  const [deactivating, setDeactivating] = useState(false);
  const [reason, setReason] = useState('');
  const [editing, setEditing] = useState(false);

  const refresh = useCallback(async () => {
    const [user, tree] = await Promise.all([fetchUser(id), fetchOrgTree()]);
    if (user.error || !user.data) return setLoad({ status: 'error', error: user.error });
    const names: Record<string, string> = {};
    for (const u of tree.data?.units ?? []) names[u.id] = u.name;
    setLoad({ status: 'ready', user: user.data, names });
  }, [id]);

  useFocusEffect(useCallback(() => {
    void refresh();
  }, [refresh]));

  const run = async (call: () => Promise<Result<unknown>>, done: string) => {
    setBusy(true);
    const { error } = await call();
    setBusy(false);
    if (error) snackbar.show({ text: errorText(error).message });
    else snackbar.show({ text: done });
    await refresh();
    return !error;
  };

  if (load.status !== 'ready') {
    return (
      <View style={{ flex: 1, backgroundColor: colors.background }}>
        <AppHeader back />
        <Screen title={t('user.title')} testID="user">
          {load.status === 'loading'
            ? <Skeleton lines={4} testID="user-loading" />
            : <ErrorState error={load.error} onRetry={() => void refresh()} testID="user-error" />}
        </Screen>
      </View>
    );
  }

  const { user, names } = load;
  const name = user.display_name ?? user.email ?? '';
  const canChange = !user.is_self && !user.outranks_you;
  const canEditContact = user.is_self || (!user.profile_shared && !user.outranks_you);
  const statusTone = { pending: 'warning', active: 'success', deactivated: 'neutral' } as const;

  const where = (a: Assignment) =>
    a.branch_id ? t('user.inBranch', { branch: names[a.branch_id] ?? '' })
      : a.org_unit_id ? t('user.inUnit', { unit: names[a.org_unit_id] ?? '' }) : t('user.everywhere');
  const dates = (a: Assignment) => [t('user.from', { date: format.dateTime(a.valid_from) }),
    a.valid_to ? t('user.until', { date: format.dateTime(a.valid_to) }) : null].filter(Boolean).join(' · ');

  const removeAssignment = async (a: Assignment) => {
    if (await confirm({ title: t('user.removeTitle', { role: roleName(a), name }), message: t('user.removeBody'),
      confirmLabel: t('user.removeRole'), danger: true })) {
      await run(() => unassignRole(a.id), t('user.removed'));
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={name} testID="user">
        <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
          <Badge label={t(`users.status.${user.status}`)} tone={statusTone[user.status]} testID="user-status" />
        </View>
        {user.is_self ? <AppText style={{ color: colors.onSurfaceVariant }}>{t('user.self')}</AppText> : null}
        {user.outranks_you ? <AppText style={{ color: colors.onSurfaceVariant }} testID="user-outranks">{t('user.outranks')}</AppText> : null}

        {canChange ? (
          <View style={{ gap: space.sm }}>
            {user.status === 'pending' ? (
              <Button label={t('user.approve')} icon="check" loading={busy} testID="user-approve" onPress={() => void (async () => {
                if (await confirm({ title: t('user.approveTitle', { name }), message: t('user.approveBody'), confirmLabel: t('user.approve') })) {
                  await run(() => approveUser(user.user_id), t('user.approved'));
                }
              })()} />
            ) : null}
            {user.status === 'deactivated' ? (
              <Button label={t('user.reactivate')} icon="restart-alt" variant="tonal" loading={busy} testID="user-reactivate"
                onPress={() => void (async () => {
                  if (await confirm({ title: t('user.reactivateTitle', { name }), message: t('user.reactivateBody'), confirmLabel: t('user.reactivate') })) {
                    await run(() => reactivateUser(user.user_id), t('user.reactivated'));
                  }
                })()} />
            ) : (
              <Button label={t('user.deactivate')} icon="block" variant="outlined" disabled={busy} testID="user-deactivate"
                onPress={() => setDeactivating(true)} />
            )}
          </View>
        ) : null}

        <Section title={t('user.contact')} testID="user-contact"
          action={canEditContact ? <Button variant="text" icon="edit" label={t('user.editContact')} onPress={() => setEditing(true)} testID="user-edit-contact" /> : null}>
          <AppText testID="user-email">{`${t('user.email')}: ${user.email ?? ''}`}</AppText>
          {user.phone ? <AppText testID="user-phone">{`${t('user.phone')}: ${format.digitsText(user.phone)}`}</AppText> : null}
          {user.status === 'pending'
            ? <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{t('users.requested', { date: format.dateTime(user.requested_at) })}</AppText>
            : null}
          {user.deactivated_at && user.status === 'deactivated'
            ? <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{t('users.deactivatedOn', { date: format.dateTime(user.deactivated_at) })}</AppText>
            : null}
          {user.profile_shared && !user.is_self ? <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{t('user.sharedProfile')}</AppText> : null}
        </Section>

        <Section title={t('user.roles')} testID="user-roles"
          action={canChange ? <Button variant="tonal" icon="add" label={t('user.addRole')} testID="user-add-role"
            onPress={() => router.push({ pathname: '/admin/assign', params: { user: user.user_id } })} /> : null}>
          {user.assignments.length === 0 ? <AppText style={{ color: colors.onSurfaceVariant }}>{t('user.noRoles')}</AppText> : null}
          {user.assignments.map((a) => (
            <View key={a.id} style={{ gap: space.xs, padding: space.md, borderRadius: 12, backgroundColor: colors.surfaceContainerLow }}
              testID={`assignment-${roleName(a)}`}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm, flexWrap: 'wrap' }}>
                <AppText variant="label" style={{ flex: 1, minWidth: 120 }}>{roleName(a)}</AppText>
                {a.state !== 'active' ? <Badge label={t(`user.state.${a.state}`)} tone={a.state === 'scheduled' ? 'primary' : 'neutral'} /> : null}
              </View>
              <AppText variant="bodySmall" testID={`assignment-${roleName(a)}-where`}>{where(a)}</AppText>
              <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{dates(a)}</AppText>
              {canChange ? <Button variant="text" icon="remove-circle-outline" label={t('user.removeRole')}
                onPress={() => void removeAssignment(a)} testID={`assignment-${roleName(a)}-remove`} /> : null}
            </View>
          ))}
        </Section>

        <Section title={t('user.units')}>
          {user.org_units.length === 0 ? <AppText style={{ color: colors.onSurfaceVariant }}>{t('user.noUnits')}</AppText> : null}
          {user.org_units.map((u) => <AppText key={u.id}>{`${u.name} · ${u.manager ? t('user.manager') : t('user.member')}`}</AppText>)}
        </Section>

        <Section title={t('user.access')} testID="user-access">
          {Object.keys(user.permissions).length === 0 ? <AppText style={{ color: colors.onSurfaceVariant }}>{t('user.noAccess')}</AppText> : null}
          {Object.entries(user.permissions).sort().map(([key, scopes]) => (
            <AppText key={key} variant="bodySmall">
              {t('user.permissionScopes', { permission: permissionLabel(key), scopes: scopes.map((s) => tDynamic(`admin:scopes.${s}`)).join(', ') })}
            </AppText>
          ))}
          <Button variant="text" icon="help-outline" label={t('user.explainLink')} testID="user-explain"
            onPress={() => router.push({ pathname: '/admin/explain', params: { user: user.user_id } })} />
        </Section>

        <Section title={t('user.more')}>
          <Row title={t('user.passwordReset')} subtitle={t('user.later')} icon="lock-reset" />
          <Row title={t('user.activity')} subtitle={t('user.later')} icon="timeline" />
          <Row title={t('user.delegation')} subtitle={t('user.later')} icon="swap-horiz" />
          <Row title={t('user.listLayout')} subtitle={t('user.later')} icon="view-list" />
          <Row title={t('user.callLogSync')} subtitle={t('user.later')} icon="call" />
        </Section>
      </Screen>

      <BottomSheet visible={deactivating} onClose={() => setDeactivating(false)} title={t('user.deactivateTitle', { name })} testID="deactivate-sheet"
        footer={<Button variant="danger" label={t('user.deactivate')} loading={busy} fullWidth testID="deactivate-confirm"
          onPress={() => void run(() => deactivateUser(user.user_id, reason), t('user.deactivated')).then(() => {
            setDeactivating(false);
            setReason('');
          })} />}>
        <AppText>{t('user.deactivateBody')}</AppText>
        <TextField label={t('user.reason')} kind="multiline" value={reason} onChangeText={setReason} maxLength={500} testID="deactivate-reason" />
      </BottomSheet>
      {editing ? <ContactSheet user={user} onClose={() => setEditing(false)} onSaved={() => void refresh()} /> : null}
    </View>
  );
}

function ContactSheet({ user, onClose, onSaved }: { user: UserDetail; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('admin');
  const errorText = useErrorText();
  const snackbar = useSnackbar();
  const [name, setName] = useState(user.display_name ?? '');
  const [phone, setPhone] = useState<string | null>(user.phone);
  const [email, setEmail] = useState(user.email ?? '');
  const [error, setError] = useState<{ field: 'name' | 'phone' | 'email' | 'form'; text: string } | null>(null);
  const [saving, setSaving] = useState(false);
  const save = async () => {
    setSaving(true);
    const result = await updateContact(user.user_id, { name, phone: phone ?? '', email });
    setSaving(false);
    if (result.error) {
      const code = result.error.code;
      const field = code === 'phone_invalid' ? 'phone' : code === 'email_invalid' || code === 'email_taken' ? 'email'
        : code === 'user_contact_invalid' ? 'name' : 'form';
      setError({ field, text: errorText(result.error).message });
      if (field === 'form') describeError(result.error, 'users.contact');
      return;
    }
    snackbar.show({ text: t('user.contactSaved') });
    onSaved();
    onClose();
  };
  return (
    <BottomSheet visible onClose={onClose} title={t('user.editContact')} testID="contact-sheet"
      footer={<Button label={t('user.saveContact')} loading={saving} fullWidth onPress={() => void save()} testID="contact-save" />}>
      <TextField label={t('user.name')} kind="name" required value={name} onChangeText={setName} maxLength={120}
        error={error?.field === 'name' ? error.text : null} testID="contact-name" />
      <PhoneInput label={t('user.phone')} value={phone} onChange={setPhone} errorText={error?.field === 'phone' ? error.text : undefined}
        testID="contact-phone" />
      <TextField label={t('user.email')} kind="email" required value={email} onChangeText={setEmail} help={t('user.emailHelp')}
        error={error?.field === 'email' || error?.field === 'form' ? error.text : null} last onDone={() => void save()} testID="contact-email" />
    </BottomSheet>
  );
}
