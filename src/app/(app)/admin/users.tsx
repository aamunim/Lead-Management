import { router } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { normaliseSearch } from '@/lib/admin-core';
import { fetchUsers, type UserList, type UserListItem, type UserStatus } from '@/lib/admin';
import { useFormat } from '@/lib/locale';
import { Badge, Chips, Row, roleName } from '@/ui/admin/parts';
import { EmptyState, StateList, TextField } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';
import { MAX_CONTENT_WIDTH } from '@/ui/tokens/layout';

// Settings → Users (0A.18-T1, Ch 11.14): pending / active / deactivated people with search. Every state is handled:
// skeleton while loading, error with Retry, empty with a hint, pull to refresh.
type Filter = 'all' | UserStatus;
type State = { status: 'loading' } | { status: 'error'; error: unknown } | { status: 'ready'; items: UserListItem[] };

export default function UsersScreen() {
  const { t } = useTranslation('admin');
  const { colors, space } = useTheme();
  const format = useFormat();
  const [filter, setFilter] = useState<Filter>('all');
  const [query, setQuery] = useState('');
  const [search, setSearch] = useState('');
  const [state, setState] = useState<State>({ status: 'loading' });
  const [counts, setCounts] = useState<UserList['counts'] | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => {
    const timer = setTimeout(() => setSearch(normaliseSearch(query)), 300);
    return () => clearTimeout(timer);
  }, [query]);

  const load = useCallback(async (quiet = false) => {
    if (!quiet) setState({ status: 'loading' });
    const { data, error } = await fetchUsers(filter === 'all' ? null : filter, search);
    if (error || !data) setState({ status: 'error', error });
    else {
      setCounts(data.counts);
      setState({ status: 'ready', items: data.items });
    }
  }, [filter, search]);

  useEffect(() => {
    void load();
  }, [load]);

  const total = counts ? counts.pending + counts.active + counts.deactivated : 0;
  const n = (v: number | undefined) => format.number(v ?? 0);
  const statusTone = { pending: 'warning', active: 'success', deactivated: 'neutral' } as const;

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <View style={{ flex: 1, width: '100%', maxWidth: MAX_CONTENT_WIDTH, alignSelf: 'center', padding: space.lg, gap: space.md }} testID="users">
        <AppText variant="headline" accessibilityRole="header" testID="users-title">{t('users.title')}</AppText>
        <TextField label={t('users.search')} kind="search" value={query} onChangeText={setQuery} last testID="users-search" />
        <Chips label={t('users.filter')} selected={filter} onSelect={setFilter} choices={[
          { value: 'all', label: t('users.filters.all', { count: n(total) }), testID: 'users-filter-all' },
          { value: 'pending', label: t('users.filters.pending', { count: n(counts?.pending) }), testID: 'users-filter-pending' },
          { value: 'active', label: t('users.filters.active', { count: n(counts?.active) }), testID: 'users-filter-active' },
          { value: 'deactivated', label: t('users.filters.deactivated', { count: n(counts?.deactivated) }), testID: 'users-filter-deactivated' },
        ]} />
        <View style={{ flex: 1 }}>
          <StateList
            state={state}
            refreshing={refreshing}
            onRefresh={() => {
              setRefreshing(true);
              void load(true).finally(() => setRefreshing(false));
            }}
            testID="users-list"
            keyExtractor={(u) => u.user_id}
            ItemSeparatorComponent={() => <View style={{ height: space.sm }} />}
            empty={search
              ? <EmptyState icon="search-off" title={t('users.emptySearch', { query: search })} testID="users-empty" />
              : <EmptyState icon="group-add" title={t('users.empty')} body={t('users.emptyBody')} testID="users-empty" />}
            renderItem={({ item }) => (
              <Row
                title={item.display_name ?? item.email ?? ''}
                subtitle={[
                  item.roles.length ? item.roles.map(roleName).join(', ') : t('users.noRole'),
                  item.phone ? format.digitsText(item.phone) : null,
                  item.status === 'pending' ? t('users.requested', { date: format.dateTime(item.requested_at) }) : null,
                ].filter(Boolean).join(' · ')}
                icon="account-circle"
                badge={item.status === 'active' ? undefined : <Badge label={t(`users.status.${item.status}`)} tone={statusTone[item.status]} />}
                onPress={() => router.push({ pathname: '/admin/user/[id]', params: { id: item.user_id } })}
                testID={`user-${item.display_name ?? item.user_id}`}
              />
            )}
          />
        </View>
      </View>
    </View>
  );
}
