import { useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useColors } from '@/components/theme';
import { useTranslation } from '@/i18n';
import { localDateOf, monthGrid, parseDateOnly, weekdayOrder, zonedParts, zonedToEpoch } from '@/lib/format';
import { useFormat } from '@/lib/locale';
import { serverNow } from '@/lib/server-time';

// Date and date-time pickers (0A.11-T5), written in JS so they look and behave the same on Android and web, in
// Bangla and English. The week starts on the institution's week_start; "today" is the institution's date from the
// server clock (never the phone clock or the phone's time zone).
//
// - DateField: a date-only value 'YYYY-MM-DD' (birthday, instalment date). Never shifted by a time zone.
// - DateTimeField: an instant (ISO string, UTC). Chosen and shown in the institution's time zone.

type Props<T> = { label: string; value: T | null; onChange: (value: T) => void; testID?: string };

const pad2 = (n: number) => String(n).padStart(2, '0');

function Calendar({ selected, onSelect, testID }: { selected: string | null; onSelect: (date: string) => void; testID?: string }) {
  const format = useFormat();
  const colors = useColors();
  const { t } = useTranslation('locale');
  const timeZone = format.locale?.time_zone ?? 'UTC';
  const today = localDateOf(serverNow(), timeZone);
  const start = parseDateOnly(selected ?? today) ?? parseDateOnly(today)!;
  const [view, setView] = useState({ year: start.year, month: start.month });
  const weekStart = format.locale?.week_start ?? 'sunday';
  const move = (delta: number) => {
    const index = view.year * 12 + (view.month - 1) + delta;
    setView({ year: Math.floor(index / 12), month: (index % 12) + 1 });
  };
  return (
    <View style={styles.calendar} testID={testID}>
      <View style={styles.monthRow}>
        <Pressable accessibilityRole="button" accessibilityLabel={t('picker.previousMonth')} onPress={() => move(-1)} style={styles.navButton}>
          <AppText style={styles.nav}>‹</AppText>
        </Pressable>
        <AppText style={styles.monthTitle} testID={testID ? `${testID}-month` : undefined}>
          {`${format.words.months[view.month - 1]} ${format.digitsText(view.year)}`}
        </AppText>
        <Pressable accessibilityRole="button" accessibilityLabel={t('picker.nextMonth')} onPress={() => move(1)} style={styles.navButton}>
          <AppText style={styles.nav}>›</AppText>
        </Pressable>
      </View>
      <View style={styles.week}>
        {weekdayOrder(weekStart).map((day) => (
          <AppText key={day} style={[styles.cell, styles.weekday, { color: colors.muted }]}>{format.words.weekdaysShort[day]}</AppText>
        ))}
      </View>
      {monthGrid(view.year, view.month, weekStart).map((week, row) => (
        <View key={row} style={styles.week}>
          {week.map((date, col) => {
            if (!date) return <View key={col} style={styles.cell} />;
            const isSelected = date === selected;
            const isToday = date === today;
            return (
              <Pressable
                key={date}
                accessibilityRole="button"
                accessibilityLabel={format.date(date)}
                accessibilityState={{ selected: isSelected }}
                onPress={() => onSelect(date)}
                style={[styles.cell, styles.day, isToday && { borderColor: colors.accent, borderWidth: 1 },
                  isSelected && { backgroundColor: colors.accent }]}
                testID={`day-${date}`}
              >
                <AppText style={isSelected ? { color: colors.accentText } : undefined}>{format.digitsText(Number(date.slice(8)))}</AppText>
              </Pressable>
            );
          })}
        </View>
      ))}
    </View>
  );
}

function TimeChooser({ hour, minute, onChange }: { hour: number; minute: number; onChange: (h: number, m: number) => void }) {
  const format = useFormat();
  const colors = useColors();
  const { t } = useTranslation('locale');
  const chip = (selected: boolean) => [styles.chip, { borderColor: colors.border }, selected && { backgroundColor: colors.accent, borderColor: colors.accent }];
  return (
    <View style={styles.timeBox}>
      <AppText style={styles.timeLabel}>{t('picker.hour')}</AppText>
      <ScrollView horizontal contentContainerStyle={styles.chips}>
        {Array.from({ length: 24 }, (_, h) => (
          <Pressable key={h} style={chip(h === hour)} onPress={() => onChange(h, minute)} testID={`hour-${h}`}>
            <AppText style={h === hour ? { color: colors.accentText } : undefined}>{format.time(h, 0)}</AppText>
          </Pressable>
        ))}
      </ScrollView>
      <AppText style={styles.timeLabel}>{t('picker.minute')}</AppText>
      <View style={styles.chipsWrap}>
        {Array.from({ length: 12 }, (_, i) => i * 5).map((m) => (
          <Pressable key={m} style={chip(m === minute)} onPress={() => onChange(hour, m)} testID={`minute-${m}`}>
            <AppText style={m === minute ? { color: colors.accentText } : undefined}>{format.digitsText(pad2(m))}</AppText>
          </Pressable>
        ))}
      </View>
    </View>
  );
}

function PickerShell({ label, shown, open, setOpen, onDone, children, testID }: {
  label: string; shown: string; open: boolean; setOpen: (open: boolean) => void; onDone: () => void;
  children: React.ReactNode; testID?: string;
}) {
  const colors = useColors();
  const { t } = useTranslation('locale');
  const { t: tCommon } = useTranslation();
  return (
    <View style={styles.field}>
      <AppText style={styles.label}>{label}</AppText>
      <Pressable
        accessibilityRole="button"
        style={[styles.box, { borderColor: colors.border, backgroundColor: colors.surface }]}
        onPress={() => setOpen(true)}
        testID={testID}
      >
        <AppText testID={testID ? `${testID}-value` : undefined}>{shown}</AppText>
      </Pressable>
      <Modal visible={open} transparent animationType="fade" onRequestClose={() => setOpen(false)}>
        <View style={styles.backdrop}>
          <View style={[styles.sheet, { backgroundColor: colors.surface }]}>
            <AppText style={styles.sheetTitle}>{label}</AppText>
            {children}
            <View style={styles.actions}>
              <Pressable style={[styles.action, { borderColor: colors.border }]} onPress={() => setOpen(false)}>
                <AppText>{tCommon('actions.cancel')}</AppText>
              </Pressable>
              <Pressable style={[styles.action, { backgroundColor: colors.accent, borderColor: colors.accent }]} onPress={onDone}
                testID={testID ? `${testID}-done` : undefined}>
                <AppText style={{ color: colors.accentText }}>{t('picker.done')}</AppText>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
}

/** Date-only field: value 'YYYY-MM-DD'. */
export function DateField({ label, value, onChange, testID }: Props<string>) {
  const format = useFormat();
  const { t } = useTranslation('locale');
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState<string | null>(value);
  return (
    <PickerShell label={label} shown={value ? format.date(value) : t('fields.empty')} open={open}
      setOpen={(next) => { setDraft(value); setOpen(next); }}
      onDone={() => { if (draft) onChange(draft); setOpen(false); }} testID={testID}>
      <Calendar selected={draft} onSelect={setDraft} testID={testID ? `${testID}-calendar` : undefined} />
    </PickerShell>
  );
}

/** Date-time field: value is an ISO instant (UTC); chosen and shown in the institution's time zone. */
export function DateTimeField({ label, value, onChange, testID }: Props<string>) {
  const format = useFormat();
  const { t } = useTranslation('locale');
  const timeZone = format.locale?.time_zone ?? 'UTC';
  const [open, setOpen] = useState(false);
  const initial = () => {
    const p = zonedParts(value ? Date.parse(value) : serverNow(), timeZone);
    return { date: `${p.year}-${pad2(p.month)}-${pad2(p.day)}`, hour: p.hour, minute: p.minute - (p.minute % 5) };
  };
  const [draft, setDraft] = useState(initial);
  return (
    <PickerShell label={label} shown={value ? format.dateTime(value) : t('fields.empty')} open={open}
      setOpen={(next) => { setDraft(initial()); setOpen(next); }}
      onDone={() => {
        const d = parseDateOnly(draft.date);
        if (d) onChange(new Date(zonedToEpoch({ ...d, hour: draft.hour, minute: draft.minute }, timeZone)).toISOString());
        setOpen(false);
      }} testID={testID}>
      <Calendar selected={draft.date} onSelect={(date) => setDraft({ ...draft, date })} />
      <TimeChooser hour={draft.hour} minute={draft.minute} onChange={(hour, minute) => setDraft({ ...draft, hour, minute })} />
    </PickerShell>
  );
}

const styles = StyleSheet.create({
  field: { gap: 6 },
  label: { fontSize: 14, fontWeight: '600' },
  box: { minHeight: 48, borderWidth: 1, borderRadius: 8, paddingHorizontal: 12, justifyContent: 'center' },
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.45)', justifyContent: 'center', padding: 16 },
  sheet: { borderRadius: 12, padding: 16, gap: 12, maxWidth: 420, width: '100%', alignSelf: 'center' },
  sheetTitle: { fontSize: 18, fontWeight: '600' },
  calendar: { gap: 4 },
  monthRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  monthTitle: { fontSize: 16, fontWeight: '600' },
  navButton: { minWidth: 48, minHeight: 48, alignItems: 'center', justifyContent: 'center' },
  nav: { fontSize: 24 },
  week: { flexDirection: 'row' },
  cell: { flex: 1, minHeight: 40, alignItems: 'center', justifyContent: 'center', textAlign: 'center' },
  weekday: { fontSize: 12 },
  day: { borderRadius: 20 },
  timeBox: { gap: 6 },
  timeLabel: { fontSize: 13, fontWeight: '600' },
  chips: { gap: 6, paddingVertical: 2 },
  chipsWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  chip: { minHeight: 40, minWidth: 48, borderWidth: 1, borderRadius: 20, paddingHorizontal: 10, alignItems: 'center', justifyContent: 'center' },
  actions: { flexDirection: 'row', justifyContent: 'flex-end', gap: 8 },
  action: { minHeight: 44, borderWidth: 1, borderRadius: 8, paddingHorizontal: 16, justifyContent: 'center' },
});
