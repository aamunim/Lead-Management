import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { useFormat } from '@/lib/locale';
import {
  cancelPlatformInvite, fetchPlatformUsers, invitePlatformUser, updatePlatformUser, type PlatformRole, type PlatformUser,
} from '@/lib/platform';
import { Badge, CheckRow, Row, SelectField } from '@/ui/admin/parts';
import { BottomSheet, Button, ErrorState, Skeleton, TextField, useSnackbar } from '@/ui/components';
import { usePanel } from '@/ui/panel/PanelContext';
import { PanelShell } from '@/ui/panel/PanelShell';

// Platform users (0B.02-T7): one person per account, invited by email; change role, setup rights, deactivate.
// Guards on the server: only a Master Admin makes or changes a Master Admin, nobody changes themselves, the last
// Master Admin stays, deactivation ends the person's sessions; every change is in the platform audit log.
const ROLES: PlatformRole[] = ['master_admin', 'support', 'billing', 'developer'];
type Data = Awaited<ReturnType<typeof fetchPlatformUsers>>['data'];

export default function PlatformUsers() {
  const { t } = useTranslation('panel');
  const format = useFormat();
  const { state } = usePanel();
  const [data, setData] = useState<Data>(null);
  const [error, setError] = useState<unknown>(null);
  const [inviting, setInviting] = useState(false);
  const [editing, setEditing] = useState<PlatformUser | null>(null);
  const snackbar = useSnackbar();
  const errorText = useErrorText();

  const load = useCallback(async () => {
    setError(null);
    const r = await fetchPlatformUsers();
    if (r.error) setError(r.error);
    else setData(r.data);
  }, []);
  useEffect(() => {
    if (state.status === 'ready') void load();
  }, [state.status, load]);
  const roleChoices = ROLES.map((r) => ({ value: r, label: `${t(`roles.${r}`)} — ${t(`roleHelp.${r}`)}`, testID: `role-${r}` }));

  return (
    <PanelShell permission="platform.users" title={t('users.title')} testID="panel-users">
      <AppText>{t('users.intro')}</AppText>
      <Button icon="person-add" label={t('users.invite')} onPress={() => setInviting(true)} testID="panel-users-invite" />
      {error ? <ErrorState error={error} onRetry={() => void load()} /> : !data ? <Skeleton lines={4} /> : (
        <View style={{ gap: 8 }}>
          {data.users.map((u) => (
            <Row key={u.user_id} icon="person" title={u.email} testID={`platform-user-${u.email}`}
              onPress={state.status === 'ready' && u.user_id !== state.session.user_id ? () => setEditing(u) : undefined}
              subtitle={[t(`roles.${u.platform_role}`), u.last_seen ? t('users.lastSeen', { date: format.dateTime(u.last_seen) }) : null,
                u.extra_permissions.includes('platform.support_access') ? t('users.setupRights') : null].filter(Boolean).join(' · ')}
              badge={u.status === 'deactivated' ? <Badge label={t('users.status.deactivated')} />
                : !u.has_second_factor ? <Badge label={t('users.noSecondFactor')} tone="warning" /> : undefined} />
          ))}
          {data.invites.length ? <AppText variant="titleSmall">{t('users.invites')}</AppText> : null}
          {data.invites.map((i) => (
            <Row key={i.email} icon="mail-outline" title={i.email} subtitle={t(`roles.${i.platform_role}`)} testID={`platform-invite-${i.email}`}
              badge={<Button variant="text" label={t('users.cancelInvite')} onPress={() => void cancelPlatformInvite(i.email).then(load)} />} />
          ))}
        </View>
      )}
      {inviting ? (
        <InviteSheet roleChoices={roleChoices} onClose={() => setInviting(false)} onDone={() => {
          setInviting(false);
          snackbar.show({ text: t('users.invited') });
          void load();
        }} />
      ) : null}
      {editing ? (
        <EditSheet user={editing} roleChoices={roleChoices} onClose={() => setEditing(null)} onDone={(msg) => {
          setEditing(null);
          snackbar.show({ text: msg ? errorText(msg).message : t('users.saved') });
          void load();
        }} />
      ) : null}
    </PanelShell>
  );
}

function InviteSheet({ roleChoices, onClose, onDone }: {
  roleChoices: { value: PlatformRole; label: string; testID: string }[]; onClose: () => void; onDone: () => void;
}) {
  const { t } = useTranslation('panel');
  const errorText = useErrorText();
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<PlatformRole>('support');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const save = async () => {
    setBusy(true);
    const r = await invitePlatformUser(email, role);
    setBusy(false);
    if (r.error) return setError(errorText(r.error).message);
    onDone();
  };
  return (
    <BottomSheet visible onClose={onClose} title={t('users.inviteTitle')} testID="invite-sheet"
      footer={<Button label={t('users.invite')} loading={busy} fullWidth onPress={() => void save()} testID="invite-save" />}>
      <TextField label={t('users.email')} kind="email" required value={email} onChangeText={setEmail} error={error} testID="invite-email" />
      <SelectField label={t('users.role')} value={role} onChange={setRole} choices={roleChoices} testID="invite-role" />
    </BottomSheet>
  );
}

function EditSheet({ user, roleChoices, onClose, onDone }: {
  user: PlatformUser; roleChoices: { value: PlatformRole; label: string; testID: string }[]; onClose: () => void; onDone: (error?: Parameters<ReturnType<typeof useErrorText>>[0]) => void;
}) {
  const { t } = useTranslation('panel');
  const [role, setRole] = useState<PlatformRole>(user.platform_role);
  const [setup, setSetup] = useState(user.extra_permissions.includes('platform.support_access'));
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const save = async (status: 'active' | 'deactivated') => {
    setBusy(true);
    const extra = [...user.extra_permissions.filter((p) => p !== 'platform.support_access'), ...(setup ? ['platform.support_access'] : [])];
    const r = await updatePlatformUser(user.user_id, role, status, extra, reason.trim() || null);
    setBusy(false);
    onDone(r.error ?? undefined);
  };
  return (
    <BottomSheet visible onClose={onClose} title={user.email} testID="edit-sheet"
      footer={<Button label={t('users.save')} loading={busy} fullWidth onPress={() => void save(user.status)} testID="edit-save" />}>
      <SelectField label={t('users.role')} value={role} onChange={setRole} choices={roleChoices} testID="edit-role" />
      <CheckRow label={t('users.setupRights')} checked={setup} onToggle={() => setSetup((v) => !v)} testID="edit-setup" />
      <TextField label={t('users.reason')} kind="multiline" value={reason} onChangeText={setReason} maxLength={300} testID="edit-reason" />
      <Button variant={user.status === 'active' ? 'danger' : 'tonal'} label={user.status === 'active' ? t('users.deactivate') : t('users.reactivate')}
        loading={busy} onPress={() => void save(user.status === 'active' ? 'deactivated' : 'active')} testID="edit-status" />
    </BottomSheet>
  );
}
