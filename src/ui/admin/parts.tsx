import { MaterialIcons } from '@expo/vector-icons';
import { useState, type ReactNode } from 'react';
import { Pressable, ScrollView, View } from 'react-native';

import { AppText } from '@/components/AppText';
import i18n, { useTranslation } from '@/i18n';
import { permissionTextKey } from '@/lib/admin-core';
import { BottomSheet, ChoiceList, Field, type Choice, type IconName } from '@/ui/components';
import { useTheme } from '@/ui/theme';

// Small building blocks shared by the Users / Roles / explainer / change log screens (0A.18).

/** Translate a key that comes from the server (role name_key, permission keys): checked by check:i18n / manifests. */
export function tDynamic(key: string, options?: Record<string, unknown>): string {
  return (i18n.t as unknown as (k: string, o?: Record<string, unknown>) => string)(key, options);
}

/** A role's shown name: its own name, else the translated name of its template (labels follow the institution). */
export function roleName(role: { name?: string | null; name_key?: string | null; role_name?: string | null; role_name_key?: string | null }): string {
  const name = role.name ?? role.role_name;
  if (name) return name;
  const key = role.name_key ?? role.role_name_key;
  return key ? tDynamic(key) : '';
}

export function permissionLabel(key: string): string {
  return tDynamic(`permissions:${permissionTextKey(key, 'label')}`);
}
export function permissionHelp(key: string): string {
  return tDynamic(`permissions:${permissionTextKey(key, 'help')}`);
}

export function Section({ title, children, action, testID }: { title: string; children: ReactNode; action?: ReactNode; testID?: string }) {
  const { colors, space } = useTheme();
  return (
    <View style={{ gap: space.md, paddingTop: space.lg, borderTopWidth: 1, borderTopColor: colors.outlineVariant }} testID={testID}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm, flexWrap: 'wrap' }}>
        <AppText variant="titleSmall" accessibilityRole="header" style={{ flex: 1, minWidth: 160 }}>{title}</AppText>
        {action}
      </View>
      {children}
    </View>
  );
}

/** A tappable row: icon, title, a line under it, an optional badge, and a chevron (48 dp or taller). */
export function Row({ title, subtitle, icon, badge, onPress, testID }: {
  title: string; subtitle?: string | null; icon?: IconName; badge?: ReactNode; onPress?: () => void; testID?: string;
}) {
  const { colors, radius, space, touch } = useTheme();
  const body = (
    <>
      {icon ? <MaterialIcons name={icon} size={24} color={colors.onSurfaceVariant} /> : null}
      <View style={{ flex: 1, gap: 2, minWidth: 0 }}>
        <AppText>{title}</AppText>
        {subtitle ? <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{subtitle}</AppText> : null}
      </View>
      {badge}
      {onPress ? <MaterialIcons name="chevron-right" size={24} color={colors.onSurfaceVariant} /> : null}
    </>
  );
  const style = { minHeight: touch, flexDirection: 'row' as const, alignItems: 'center' as const, gap: space.md, paddingHorizontal: space.lg,
    paddingVertical: space.sm, borderRadius: radius.md };
  if (!onPress) return <View style={[style, { backgroundColor: colors.surfaceContainerLow }]} testID={testID}>{body}</View>;
  return (
    <Pressable accessibilityRole="button" accessibilityLabel={subtitle ? `${title}, ${subtitle}` : title} onPress={onPress} testID={testID}
      style={({ pressed }) => [style, { backgroundColor: pressed ? colors.surfaceContainerHigh : colors.surfaceContainerLow }]}>
      {body}
    </Pressable>
  );
}

/** A short coloured tag ("Sensitive", "Waiting for approval"); text + icon, never colour alone. */
export function Badge({ label, tone = 'neutral', icon, testID }: {
  label: string; tone?: 'neutral' | 'warning' | 'error' | 'success' | 'primary'; icon?: IconName; testID?: string;
}) {
  const { colors, radius, space } = useTheme();
  const palette = {
    neutral: [colors.surfaceContainerHigh, colors.onSurfaceVariant],
    warning: [colors.warmContainer, colors.onWarmContainer],
    error: [colors.errorContainer, colors.onErrorContainer],
    success: [colors.successContainer, colors.onSuccessContainer],
    primary: [colors.primaryContainer, colors.onPrimaryContainer],
  }[tone];
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.xs, backgroundColor: palette[0], borderRadius: radius.full,
      paddingHorizontal: space.sm, paddingVertical: 2, alignSelf: 'flex-start', maxWidth: '100%' }} testID={testID}>
      {icon ? <MaterialIcons name={icon} size={14} color={palette[1]} /> : null}
      <AppText variant="caption" style={{ color: palette[1], flexShrink: 1 }}>{label}</AppText>
    </View>
  );
}

/** Filter chips in a row that scrolls sideways; the selected one is shown by border + check icon. */
export function Chips<T extends string>({ choices, selected, onSelect, label }: {
  choices: Choice<T>[]; selected: T; onSelect: (value: T) => void; label: string;
}) {
  const { colors, radius, space } = useTheme();
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} accessibilityLabel={label} contentContainerStyle={{ gap: space.sm }}>
      {choices.map((c) => {
        const on = c.value === selected;
        return (
          <Pressable key={c.value} accessibilityRole="radio" accessibilityState={{ selected: on, checked: on }} accessibilityLabel={c.label}
            onPress={() => onSelect(c.value)} testID={c.testID}
            style={{ minHeight: 40, flexDirection: 'row', alignItems: 'center', gap: space.xs, paddingHorizontal: space.md,
              borderRadius: radius.full, borderWidth: 1, borderColor: on ? colors.primary : colors.outlineVariant,
              backgroundColor: on ? colors.primaryContainer : colors.surfaceContainerLow }}>
            {on ? <MaterialIcons name="check" size={16} color={colors.onPrimaryContainer} /> : null}
            <AppText variant="label" style={{ color: on ? colors.onPrimaryContainer : colors.onSurface }}>{c.label}</AppText>
          </Pressable>
        );
      })}
    </ScrollView>
  );
}

/** A field that opens a sheet with one-of-many choices (role, branch, person…). */
export function SelectField<T extends string>({ label, value, choices, onChange, placeholder, help, testID }: {
  label: string; value: T | null; choices: Choice<T>[]; onChange: (value: T) => void; placeholder?: string; help?: string; testID?: string;
}) {
  const { colors, radius, space, touch } = useTheme();
  const { t } = useTranslation('admin');
  const [open, setOpen] = useState(false);
  const shown = choices.find((c) => c.value === value)?.label ?? placeholder ?? t('pick.choose');
  return (
    <Field label={label} help={help} testID={testID}>
      <Pressable accessibilityRole="button" accessibilityLabel={`${label}: ${shown}`} onPress={() => setOpen(true)}
        testID={testID ? `${testID}-open` : undefined}
        style={{ minHeight: touch, flexDirection: 'row', alignItems: 'center', gap: space.sm, paddingHorizontal: space.md,
          borderRadius: radius.sm, borderWidth: 1, borderColor: colors.outline, backgroundColor: colors.surfaceContainerLow }}>
        <AppText style={{ flex: 1, color: value === null ? colors.onSurfaceVariant : colors.onSurface }} testID={testID ? `${testID}-value` : undefined}>
          {shown}
        </AppText>
        <MaterialIcons name="arrow-drop-down" size={24} color={colors.onSurfaceVariant} />
      </Pressable>
      <BottomSheet visible={open} onClose={() => setOpen(false)} title={label} testID={testID ? `${testID}-sheet` : undefined}>
        <ChoiceList choices={choices} selected={value as T} accessibilityLabel={label}
          onSelect={(v) => { onChange(v); setOpen(false); }} />
      </BottomSheet>
    </Field>
  );
}

/** A check box row (48 dp): label, optional help and badge; state read by screen readers. */
export function CheckRow({ label, help, checked, onToggle, badge, disabled, testID }: {
  label: string; help?: string; checked: boolean; onToggle: () => void; badge?: ReactNode; disabled?: boolean; testID?: string;
}) {
  const { colors, space, touch } = useTheme();
  return (
    <Pressable accessibilityRole="checkbox" accessibilityState={{ checked, disabled }} aria-checked={checked} accessibilityLabel={label} accessibilityHint={help}
      onPress={onToggle} disabled={disabled} testID={testID}
      style={({ pressed }) => ({ minHeight: touch, flexDirection: 'row', alignItems: 'flex-start', gap: space.md, paddingVertical: space.sm,
        opacity: disabled ? 0.6 : pressed ? 0.85 : 1 })}>
      <MaterialIcons name={checked ? 'check-box' : 'check-box-outline-blank'} size={24} color={checked ? colors.primary : colors.onSurfaceVariant} />
      <View style={{ flex: 1, gap: 2, minWidth: 0 }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm, flexWrap: 'wrap' }}>
          <AppText style={{ flexShrink: 1 }}>{label}</AppText>
          {badge}
        </View>
        {help ? <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{help}</AppText> : null}
      </View>
    </Pressable>
  );
}
