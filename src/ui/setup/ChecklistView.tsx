import { Linking, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useFormat } from '@/lib/locale';
import type { Checklist, ChecklistItem } from '@/lib/setup';
import { Badge, CheckRow, tDynamic } from '@/ui/admin/parts';
import { Button } from '@/ui/components';
import { useTheme } from '@/ui/theme';

// The setup checklist (0B.10; Ch 6.5) as the institution and the panel show it: progress, each item with who does it,
// done / open / "arrives in phase N", and a short video when there is one. `canMark` decides which items this viewer
// may tick by hand (items with a rule tick themselves).
export function ChecklistProgress({ list }: { list: Checklist }) {
  const { t } = useTranslation('admin');
  const { colors, radius, space } = useTheme();
  return (
    <View style={{ gap: space.xs }} testID="checklist-progress">
      <AppText variant="label">{t('checklist.progress', { done: list.done, total: list.total, percent: list.percent })}</AppText>
      <View style={{ height: 8, borderRadius: radius.full, backgroundColor: colors.surfaceContainerHigh, overflow: 'hidden' }}
        accessibilityRole="progressbar" accessibilityValue={{ min: 0, max: 100, now: list.percent }}>
        <View style={{ width: `${list.percent}%`, height: 8, backgroundColor: colors.primary }} />
      </View>
    </View>
  );
}

export function ChecklistView({ list, canMark, onMark, busy }: {
  list: Checklist; canMark: (item: ChecklistItem) => boolean; onMark: (item: ChecklistItem, done: boolean) => void; busy?: boolean;
}) {
  const { t } = useTranslation('admin');
  const format = useFormat();
  const { space } = useTheme();
  const owner = (o: ChecklistItem['owner']) => tDynamic(`admin:checklist.owner.${o}`);
  return (
    <View style={{ gap: space.sm }} testID="checklist">
      <ChecklistProgress list={list} />
      {list.items.map((item) => {
        const later = item.state === 'later';
        const markable = !later && !item.auto && canMark(item);
        const sub = [
          tDynamic(`admin:checklist.items.${item.key}.help`),
          later ? t('checklist.later', { phase: item.available_from ?? '' }) : null,
          item.auto ? t('checklist.auto') : null,
          item.state === 'done' && item.completed_at ? t('checklist.doneBy', { date: format.dateTime(item.completed_at), by: item.completed_by ?? '—' }) : null,
        ].filter(Boolean).join(' · ');
        return (
          <View key={item.key} style={{ gap: space.xs }}>
            <CheckRow label={tDynamic(`admin:checklist.items.${item.key}.title`)} help={sub} checked={item.state === 'done'} disabled={busy || !markable}
              onToggle={() => onMark(item, item.state !== 'done')} testID={`checklist-${item.key}`}
              badge={<View style={{ flexDirection: 'row', gap: space.xs, flexWrap: 'wrap' }}>
                <Badge label={owner(item.owner)} tone={item.owner === 'master_admin' ? 'warning' : 'neutral'} />
                {item.optional ? <Badge label={t('checklist.optional')} /> : null}
              </View>} />
            {item.video_url ? (
              <Button variant="text" icon="play-circle-outline" label={t('checklist.video')} onPress={() => void Linking.openURL(item.video_url ?? '')}
                testID={`checklist-video-${item.key}`} />
            ) : null}
          </View>
        );
      })}
    </View>
  );
}
