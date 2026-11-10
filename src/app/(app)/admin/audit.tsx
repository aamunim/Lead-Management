import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { DateField } from '@/components/fields/pickers';
import { useTranslation } from '@/i18n';
import { fetchAudit, fetchRoles, fetchUsers, type AuditFilters, type AuditItem } from '@/lib/admin';
import { AUDIT_AREAS, auditChanges, type AuditArea } from '@/lib/admin-core';
import { addDays, parseDateOnly, zonedToEpoch } from '@/lib/format';
import { useFormat } from '@/lib/locale';
import { Chips, SelectField, roleName, tDynamic } from '@/ui/admin/parts';
import { Button, EmptyState, ErrorState, Screen, Skeleton } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Change log (0A.18-T7, Ch 11.14): role, assignment, people, field-rule and settings changes, filterable by area,
// person and dates (the institution's days). Ids are shown as names where the screen knows them.
const ANYONE = '__anyone__';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default function AuditScreen() {
  const { t } = useTranslation('admin');
  const { colors, space } = useTheme();
  const format = useFormat();
  const timeZone = format.locale?.time_zone ?? 'UTC';
  const [area, setArea] = useState<AuditArea>('all');
  const [actor, setActor] = useState<string>(ANYONE);
  const [from, setFrom] = useState<string | null>(null);
  const [to, setTo] = useState<string | null>(null);
  const [items, setItems] = useState<AuditItem[] | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [names, setNames] = useState<Record<string, string>>({});
  const [people, setPeople] = useState<{ value: string; label: string }[]>([]);
  const [loadingMore, setLoadingMore] = useState(false);

  useEffect(() => {
    void Promise.all([fetchUsers(null, ''), fetchRoles()]).then(([users, roles]) => {
      const map: Record<string, string> = {};
      for (const u of users.data?.items ?? []) map[u.user_id] = u.display_name ?? u.email ?? '';
      for (const r of roles.data ?? []) map[r.id] = roleName(r);
      setNames(map);
      setPeople((users.data?.items ?? []).map((u) => ({ value: u.user_id, label: u.display_name ?? u.email ?? '' })));
    });
  }, []);

  // Start of an institution day as an instant; "until" includes that whole day (start of the next one).
  const dayStart = useCallback((date: string, plusDays = 0) => {
    const d = parseDateOnly(plusDays ? addDays(date, plusDays) : date);
    return d ? new Date(zonedToEpoch(d, timeZone)).toISOString() : undefined;
  }, [timeZone]);

  const filters = useCallback((): AuditFilters => ({
    area, actor_user_id: actor === ANYONE ? undefined : actor,
    from: from ? dayStart(from) : undefined, to: to ? dayStart(to, 1) : undefined,
  }), [area, actor, from, to, dayStart]);

  const load = useCallback(async () => {
    setError(null);
    setItems(null);
    const r = await fetchAudit(filters());
    if (r.error || !r.data) return setError(r.error);
    setItems(r.data.items);
    setHasMore(r.data.has_more);
  }, [filters]);
  useEffect(() => {
    void load();
  }, [load]);

  const more = async () => {
    const last = items?.at(-1);
    if (!last) return;
    setLoadingMore(true);
    const r = await fetchAudit(filters(), { at: last.at, id: last.id });
    setLoadingMore(false);
    if (r.data) {
      setItems((cur) => [...(cur ?? []), ...r.data!.items]);
      setHasMore(r.data.has_more);
    }
  };

  const value = (v: string) => (UUID.test(v) && names[v] ? names[v] : v);
  const title = (action: string) => tDynamic(`admin:audit.actions.${action}`, { defaultValue: t('audit.actions.other') });

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('audit.title')} testID="audit">
        <Chips label={t('audit.area')} selected={area} onSelect={setArea}
          choices={AUDIT_AREAS.map((a) => ({ value: a, label: t(`audit.areas.${a}`), testID: `audit-area-${a}` }))} />
        <SelectField label={t('audit.actor')} value={actor} onChange={setActor} testID="audit-actor"
          choices={[{ value: ANYONE, label: t('audit.anyone') }, ...people]} />
        <View style={{ flexDirection: 'row', gap: space.md, flexWrap: 'wrap' }}>
          <View style={{ flex: 1, minWidth: 150 }}><DateField label={t('audit.from')} value={from} onChange={setFrom} testID="audit-from" /></View>
          <View style={{ flex: 1, minWidth: 150 }}><DateField label={t('audit.to')} value={to} onChange={setTo} testID="audit-to" /></View>
        </View>
        {from || to ? <Button variant="text" label={t('audit.clearDates')} onPress={() => { setFrom(null); setTo(null); }} testID="audit-clear-dates" /> : null}

        {error ? <ErrorState error={error} onRetry={() => void load()} testID="audit-error" />
          : !items ? <Skeleton lines={5} testID="audit-loading" />
            : items.length === 0 ? <EmptyState icon="history" title={t('audit.empty')} body={t('audit.emptyBody')} testID="audit-empty" /> : (
              <View style={{ gap: space.sm }} testID="audit-list">
                {items.map((item) => (
                  <View key={item.id} style={{ gap: space.xs, padding: space.md, borderRadius: 12, backgroundColor: colors.surfaceContainerLow }}
                    testID={`audit-${item.action}`}>
                    <AppText variant="label">{title(item.action)}</AppText>
                    <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>
                      {t('audit.by', { name: item.actor_name ?? t('audit.system'), date: format.dateTime(item.at) })}
                    </AppText>
                    {item.target_id && names[item.target_id] ? <AppText variant="bodySmall">{names[item.target_id]}</AppText> : null}
                    {auditChanges(item.before, item.after).slice(0, 8).map((c) => (
                      <AppText key={c.field} variant="bodySmall">{t('audit.change', { field: c.field, from: value(c.from), to: value(c.to) })}</AppText>
                    ))}
                    {item.reason ? <AppText variant="bodySmall">{t('audit.reason', { reason: item.reason })}</AppText> : null}
                  </View>
                ))}
                {hasMore ? <Button variant="outlined" label={t('audit.loadMore')} loading={loadingMore} onPress={() => void more()} testID="audit-more" /> : null}
              </View>
            )}
      </Screen>
    </View>
  );
}
