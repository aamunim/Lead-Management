import { MaterialIcons } from '@expo/vector-icons';
import { useEffect, useMemo, useRef, type ReactElement } from 'react';
import { AccessibilityInfo, Animated, FlatList, RefreshControl, StyleSheet, View, type FlatListProps } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { describeError } from '@/lib/errors';
import { useFormat } from '@/lib/locale';

import { useTheme } from '../theme';

import { Button, type IconName } from './Button';

// Loading, empty, error and progress states (0A.13-T6, Ch 47.5). A screen never shows a silent blank.

/** Skeleton: grey shapes in the layout of the coming content, pulsing (still when "reduce motion" is on). */
export function Skeleton({ lines = 3, testID }: { lines?: number; testID?: string }) {
  const { colors, radius, space } = useTheme();
  const { t } = useTranslation('ui');
  const pulse = useRef(new Animated.Value(0.55)).current;
  useEffect(() => {
    let loop: Animated.CompositeAnimation | null = null;
    void AccessibilityInfo.isReduceMotionEnabled().then((reduce) => {
      if (reduce) return;
      loop = Animated.loop(Animated.sequence([
        Animated.timing(pulse, { toValue: 1, duration: 700, useNativeDriver: true }),
        Animated.timing(pulse, { toValue: 0.55, duration: 700, useNativeDriver: true }),
      ]));
      loop.start();
    }).catch(() => undefined);
    return () => loop?.stop();
  }, [pulse]);
  return (
    <View accessibilityRole="progressbar" accessibilityLabel={t('states.loading')} accessibilityState={{ busy: true }}
      style={{ gap: space.md }} testID={testID}>
      {Array.from({ length: lines }, (_, i) => (
        <Animated.View key={i} style={{ opacity: pulse, gap: space.sm, flexDirection: 'row', alignItems: 'center' }}>
          <View style={{ width: 40, height: 40, borderRadius: radius.full, backgroundColor: colors.surfaceContainerHigh }} />
          <View style={{ flex: 1, gap: space.xs }}>
            <View style={{ height: 14, width: '70%', borderRadius: radius.sm, backgroundColor: colors.surfaceContainerHigh }} />
            <View style={{ height: 12, width: '45%', borderRadius: radius.sm, backgroundColor: colors.surfaceContainer }} />
          </View>
        </Animated.View>
      ))}
    </View>
  );
}

/** Empty state with a next step: "No leads yet" + "Add lead" (labels come from the label API, Ch 47.5). */
export function EmptyState({ icon = 'inbox', title, body, actionLabel, onAction, testID }: {
  icon?: IconName; title: string; body?: string; actionLabel?: string; onAction?: () => void; testID?: string;
}) {
  const { colors, space } = useTheme();
  return (
    <View style={[styles.center, { gap: space.md, padding: space.xl }]} testID={testID}>
      <MaterialIcons name={icon} size={48} color={colors.onSurfaceVariant} accessibilityElementsHidden importantForAccessibility="no" />
      <AppText variant="titleSmall" style={styles.centerText}>{title}</AppText>
      {body ? <AppText style={[styles.centerText, { color: colors.onSurfaceVariant }]}>{body}</AppText> : null}
      {actionLabel && onAction ? <Button label={actionLabel} onPress={onAction} icon="add" testID={testID ? `${testID}-action` : undefined} /> : null}
    </View>
  );
}

/** Error state: what happened (from the error contract, translated) and Retry — never silent (principle 10). */
export function ErrorState({ error, onRetry, where = 'screen', testID }: {
  error: unknown; onRetry: () => void; where?: string; testID?: string;
}) {
  const { colors, space } = useTheme();
  const { t } = useTranslation('ui');
  const errorText = useErrorText();
  const info = useMemo(() => describeError(error, where), [error, where]);
  const text = errorText(info);
  return (
    <View style={[styles.center, { gap: space.md, padding: space.xl }]} accessibilityRole="alert" testID={testID}>
      <MaterialIcons name="error-outline" size={48} color={colors.error} accessibilityElementsHidden importantForAccessibility="no" />
      <AppText variant="titleSmall" style={styles.centerText}>{t('states.errorTitle')}</AppText>
      <AppText style={[styles.centerText, { color: colors.onSurfaceVariant }]} testID={testID ? `${testID}-message` : undefined}>{text.message}</AppText>
      <Button label={info.action === 'retry' || !text.action ? t('actions.retry') : text.action} onPress={onRetry} icon="refresh"
        testID={testID ? `${testID}-retry` : undefined} />
    </View>
  );
}

type State<T> = { status: 'loading' } | { status: 'error'; error: unknown } | { status: 'ready'; items: T[] };

/** A list with every state handled: skeleton, error + Retry, empty + action, pull-to-refresh. */
export function StateList<T>({ state, onRefresh, refreshing, empty, renderItem, keyExtractor, testID, ...rest }: {
  state: State<T>; onRefresh: () => void; refreshing?: boolean; empty: ReactElement; testID?: string;
} & Pick<FlatListProps<T>, 'renderItem' | 'keyExtractor' | 'ItemSeparatorComponent' | 'ListHeaderComponent'>) {
  const { colors, space } = useTheme();
  if (state.status === 'loading') return <View style={{ padding: space.lg }}><Skeleton lines={5} testID={testID ? `${testID}-loading` : undefined} /></View>;
  if (state.status === 'error') return <ErrorState error={state.error} onRetry={onRefresh} testID={testID ? `${testID}-error` : undefined} />;
  return (
    <FlatList
      data={state.items}
      renderItem={renderItem}
      keyExtractor={keyExtractor}
      ListEmptyComponent={empty}
      refreshControl={<RefreshControl refreshing={!!refreshing} onRefresh={onRefresh} colors={[colors.primary]} tintColor={colors.primary} />}
      contentContainerStyle={state.items.length === 0 ? styles.grow : undefined}
      testID={testID}
      {...rest}
    />
  );
}

/** Long task (import, bulk send): progress in % and Cancel (Ch 47.5). progress = null while unknown. */
export function ProgressTask({ label, progress, onCancel, testID }: {
  label: string; progress: number | null; onCancel?: () => void; testID?: string;
}) {
  const { colors, radius, space } = useTheme();
  const { t } = useTranslation('ui');
  const format = useFormat();
  const percent = progress === null ? null : Math.round(Math.min(1, Math.max(0, progress)) * 100);
  return (
    <View style={{ gap: space.sm }} testID={testID}>
      <AppText variant="label">{label}</AppText>
      <View accessibilityRole="progressbar" accessibilityValue={percent === null ? undefined : { min: 0, max: 100, now: percent }}
        style={{ height: 8, borderRadius: radius.full, backgroundColor: colors.surfaceContainerHigh, overflow: 'hidden' }}>
        <View style={{ height: 8, width: `${percent ?? 30}%`, backgroundColor: colors.primary, borderRadius: radius.full }} />
      </View>
      <View style={[styles.row, { gap: space.md }]}>
        <AppText variant="caption" style={{ flex: 1, color: colors.onSurfaceVariant }} testID={testID ? `${testID}-percent` : undefined}>
          {percent === null ? t('progress.working') : t('progress.percent', { percent: format.number(percent) })}
        </AppText>
        {onCancel ? <Button variant="text" label={t('actions.cancel')} onPress={onCancel} testID={testID ? `${testID}-cancel` : undefined} /> : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  center: { alignItems: 'center', justifyContent: 'center' },
  centerText: { textAlign: 'center' },
  grow: { flexGrow: 1 },
  row: { flexDirection: 'row', alignItems: 'center' },
});
