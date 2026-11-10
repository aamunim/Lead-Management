import { Link, Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useState, type ReactNode } from 'react';
import { StyleSheet, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { AmountInput, PhoneInput } from '@/components/fields/inputs';
import { DateField, DateTimeField } from '@/components/fields/pickers';
import { devToolsEnabled } from '@/dev/flags';
import { useTranslation } from '@/i18n';
import {
  BottomSheet, Button, ChoiceList, EmptyState, ErrorState, IconButton, ProgressTask, Screen, Skeleton, TemperatureChip,
  TextField, useConfirm, useSnackbar,
} from '@/ui/components';
import { setThemePreview, useTheme } from '@/ui/theme';
import { checkBrand, type ColorRoles } from '@/ui/tokens/color';
import type { TypeRole } from '@/ui/tokens/type';

// Component gallery (0A.13-T8): every component in every state, for the owner checkpoint and the screenshot harness
// (scripts/ui/gallery.web.test.mjs: light / dark × bn / en × weird labels × large font, contrast and clipping checks).
// Developers only (hidden in production builds). URL parameters for previews: ?brand=FFF59D&fontScale=1.6
type ColorKey = { [K in keyof ColorRoles]: ColorRoles[K] extends string ? K : never }[keyof ColorRoles];
const SWATCHES: [ColorKey, ColorKey][] = [
  ['primary', 'onPrimary'], ['primaryContainer', 'onPrimaryContainer'], ['surfaceContainerHigh', 'onSurface'],
  ['inverseSurface', 'inverseOnSurface'], ['errorContainer', 'onErrorContainer'], ['successContainer', 'onSuccessContainer'],
  ['hotContainer', 'onHotContainer'], ['warmContainer', 'onWarmContainer'], ['coldContainer', 'onColdContainer'],
];
const TYPE_ROLES: TypeRole[] = ['headline', 'title', 'titleSmall', 'body', 'bodySmall', 'label', 'caption'];

export default function GalleryScreen() {
  const params = useLocalSearchParams<{ brand?: string; fontScale?: string }>();
  const { t } = useTranslation('gallery');
  const { t: tUi } = useTranslation('ui');
  const theme = useTheme();
  const { colors, space, radius, mode } = theme;
  const confirm = useConfirm();
  const snackbar = useSnackbar();
  const [brand, setBrand] = useState(params.brand ? `#${params.brand}` : '');
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [otp, setOtp] = useState('');
  const [note, setNote] = useState('');
  const [phone, setPhone] = useState<string | null>(null);
  const [amount, setAmount] = useState<string | null>(null);
  const [date, setDate] = useState<string | null>('2026-11-11');
  const [instant, setInstant] = useState<string | null>(null);
  const [choice, setChoice] = useState('hot');
  const [sheet, setSheet] = useState(false);
  const [progress, setProgress] = useState<number | null>(0.42);

  useEffect(() => {
    const scale = params.fontScale ? Number(params.fontScale) : null;
    setThemePreview({ fontScale: scale && Number.isFinite(scale) ? scale : null });
    return () => setThemePreview({ brand: null, fontScale: null });
  }, [params.fontScale]);
  useEffect(() => {
    setThemePreview({ brand: /^#[0-9a-fA-F]{6}$/.test(brand) ? brand : null });
  }, [brand]);

  if (!devToolsEnabled) return <Redirect href="/" />;
  const check = /^#[0-9a-fA-F]{6}$/.test(brand) ? checkBrand(brand, mode) : null;

  return (
    <Screen title={t('title')} intro={t('intro')} testID="gallery">
      <Section title={t('sections.palette')} id="palette">
        <TextField label={t('brand.label')} help={check ? (check.usableAsPrimary ? t('brand.ok') : t('brand.accentOnly')) : t('brand.help')}
          value={brand} onChangeText={setBrand} kind="search" testID="gallery-brand" />
        <View style={[styles.wrap, { gap: space.sm }]}>
          {SWATCHES.map(([bg, fg]) => (
            <View key={bg} style={{ backgroundColor: colors[bg], borderRadius: radius.sm, padding: space.sm, minWidth: 120 }}>
              <AppText variant="caption" style={{ color: colors[fg] }}>{bg}</AppText>
            </View>
          ))}
          <View style={{ backgroundColor: colors.accent, borderRadius: radius.sm, width: 48, height: 32 }} accessibilityElementsHidden />
        </View>
      </Section>

      <Section title={t('sections.typography')} id="typography">
        {TYPE_ROLES.map((role) => <AppText key={role} variant={role}>{t('typography.sample')}</AppText>)}
        <AppText>{t('typography.marks')}</AppText>
      </Section>

      <Section title={t('sections.buttons')} id="buttons">
        <View style={[styles.wrap, { gap: space.sm }]}>
          <Button label={t('buttons.primary')} onPress={() => undefined} icon="save" />
          <Button variant="tonal" label={t('buttons.tonal')} onPress={() => undefined} icon="note-add" />
          <Button variant="outlined" label={t('buttons.outlined')} onPress={() => undefined} icon="call" />
          <Button variant="text" label={t('buttons.text')} onPress={() => undefined} />
          <Button variant="danger" label={t('buttons.danger')} onPress={() => undefined} icon="delete" />
          <Button label={t('buttons.loading')} onPress={() => undefined} loading />
          <Button label={t('buttons.disabled')} onPress={() => undefined} disabled />
          <IconButton icon="edit" label={t('buttons.icon')} onPress={() => undefined} />
          <IconButton icon="edit" label={t('buttons.icon')} onPress={() => undefined} variant="tonal" />
        </View>
        <Button label={t('buttons.primary')} onPress={() => undefined} fullWidth />
      </Section>

      <Section title={t('sections.fields')} id="fields">
        <TextField label={t('fields.name')} kind="name" value={name} onChangeText={setName} required help={t('fields.nameHelp')}
          error={name.length === 1 ? t('fields.nameError') : null} testID="field-name" />
        <TextField label={t('fields.name')} kind="name" value="A" onChangeText={() => undefined} required error={t('fields.nameError')} />
        <TextField label={t('fields.email')} kind="email" value={email} onChangeText={setEmail} />
        <TextField label={t('fields.password')} kind="password" value={password} onChangeText={setPassword} />
        <TextField label={t('fields.otp')} kind="otp" value={otp} onChangeText={setOtp} />
        <PhoneInput label={t('fields.phone')} value={phone} onChange={setPhone} />
        <AmountInput label={t('fields.amount')} value={amount} onChange={setAmount} />
        <TextField label={t('fields.note')} kind="multiline" value={note} onChangeText={setNote} last />
      </Section>

      <Section title={t('sections.pickers')} id="pickers">
        <DateField label={t('fields.date')} value={date} onChange={setDate} testID="gallery-date" />
        <DateTimeField label={t('fields.dateTime')} value={instant} onChange={setInstant} testID="gallery-datetime" />
      </Section>

      <Section title={t('sections.chips')} id="chips">
        <View style={[styles.wrap, { gap: space.sm }]}>
          <TemperatureChip temperature="hot" />
          <TemperatureChip temperature="warm" />
          <TemperatureChip temperature="cold" />
        </View>
        <ChoiceList accessibilityLabel={t('sections.chips')} selected={choice} onSelect={setChoice} choices={[
          { value: 'hot', label: tUi('temperature.hot') }, { value: 'warm', label: tUi('temperature.warm') },
          { value: 'cold', label: tUi('temperature.cold') }]} />
      </Section>

      <Section title={t('sections.states')} id="states">
        <Skeleton lines={2} />
        <EmptyState icon="person-search" title={t('states.emptyTitle')} body={t('states.emptyBody')} actionLabel={t('states.emptyAction')}
          onAction={() => undefined} testID="gallery-empty" />
        <ErrorState error={{ code: 'network' }} onRetry={() => undefined} testID="gallery-error" />
        <ProgressTask label={t('states.progress')} progress={progress} onCancel={() => setProgress(null)} testID="gallery-progress" />
      </Section>

      <Section title={t('sections.overlays')} id="overlays">
        <Button variant="outlined" label={t('overlays.showSnackbar')} testID="gallery-snackbar"
          onPress={() => snackbar.showUndo(t('overlays.deleted'), () => snackbar.show({ text: t('overlays.restored') }))} />
        <Button variant="outlined" label={t('overlays.showDialog')} testID="gallery-dialog"
          onPress={() => void confirm({ title: t('overlays.dialogTitle'), message: t('overlays.dialogBody'), confirmLabel: tUi('actions.delete'), danger: true })} />
        <Button variant="outlined" label={t('overlays.showSheet')} onPress={() => setSheet(true)} testID="gallery-sheet" />
        <BottomSheet visible={sheet} onClose={() => setSheet(false)} title={t('overlays.sheetTitle')} testID="gallery-sheet-view"
          footer={<Button label={tUi('actions.save')} onPress={() => setSheet(false)} fullWidth />}>
          <TextField label={t('fields.name')} value={name} onChangeText={setName} />
          <TextField label={t('fields.note')} kind="multiline" value={note} onChangeText={setNote} last />
        </BottomSheet>
      </Section>

      <Section title={t('sections.form')} id="form">
        <Link href="/dev/form" testID="gallery-open-form"><AppText style={{ color: colors.primary, textDecorationLine: 'underline' }}>{t('form.open')}</AppText></Link>
      </Section>
    </Screen>
  );
}

function Section({ title, id, children }: { title: string; id: string; children: ReactNode }) {
  const { colors, space } = useTheme();
  return (
    <View style={{ gap: space.md, paddingTop: space.lg, borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.outlineVariant }}
      testID={`gallery-${id}`}>
      <AppText variant="title" accessibilityRole="header">{title}</AppText>
      {children}
    </View>
  );
}

const styles = StyleSheet.create({ wrap: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center' } });
