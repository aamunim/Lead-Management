import { Image } from 'expo-image';
import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { useAuthState } from '@/lib/auth-state';
import { refreshInstitutionInfo } from '@/lib/institution';
import { canPickImage, pickImage } from '@/lib/pick-image';
import { loadSettings } from '@/lib/settings';
import { fetchBranding, logoUrl, saveBrandColor, saveBranding, uploadLogo, type Branding } from '@/lib/setup';
import { Chips, Section } from '@/ui/admin/parts';
import { Button, ErrorState, Screen, Skeleton, TextField, useSnackbar } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';
import { BRAND_PRESETS, checkBrand, parseHex } from '@/ui/tokens/color';

// Settings → Branding (0B.10-T6; Ch 5.16, D12): name, short name, logo and colour, shown after sign-in in the header, the
// web tab title and later receipts and forms. The sign-in page keeps the neutral product brand. A colour without enough
// contrast in light or dark is used for accents only (checked here and in the theme).
const MAX_LOGO_BYTES = 1024 * 1024;

export default function BrandingScreen() {
  const { t } = useTranslation('admin');
  const { colors, radius, space } = useTheme();
  const auth = useAuthState();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [data, setData] = useState<Branding | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [form, setForm] = useState({ name: '', short: '', color: '' });
  const [logo, setLogo] = useState<{ path: string } | 'clear' | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const institutionId = auth.status === 'signedIn' ? auth.claims.active_institution_id ?? null : null;

  const load = useCallback(async () => {
    setError(null);
    const r = await fetchBranding();
    if (r.error || !r.data) return setError(r.error);
    setData(r.data);
    setForm({ name: r.data.name, short: r.data.short_name ?? '', color: r.data.brand_color });
    setLogo(null);
    setPreview(r.data.logo_path ? await logoUrl(r.data.logo_path) : null);
  }, []);
  useEffect(() => {
    void load();
  }, [load]);

  const color = parseHex(form.color) ? form.color.toUpperCase() : null;
  const light = color ? checkBrand(color, 'light') : null;
  const dark = color ? checkBrand(color, 'dark') : null;

  const chooseLogo = async () => {
    if (!institutionId) return;
    const picked = await pickImage();
    if (!picked) return;
    if (picked.file.size > MAX_LOGO_BYTES) return snackbar.show({ text: t('branding.logoTooBig') });
    setBusy(true);
    const r = await uploadLogo(institutionId, picked.file, picked.extension);
    setBusy(false);
    if ('error' in r) return snackbar.show({ text: errorText(r.error).message });
    setLogo(r);
    setPreview(await logoUrl(r.path));
  };

  const save = async () => {
    if (!data) return;
    setBusy(true);
    const r = await saveBranding(form.name, form.short, logo);
    const c = !r.error && color && color !== data.brand_color.toUpperCase() ? await saveBrandColor(color) : null;
    setBusy(false);
    const failed = r.error ?? c?.error;
    if (failed) return snackbar.show({ text: errorText(failed).message });
    await loadSettings(true);
    refreshInstitutionInfo();
    snackbar.show({ text: t('branding.saved') });
    void load();
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('branding.title')} intro={t('branding.intro')} testID="branding">
        {error ? <ErrorState error={error} onRetry={() => void load()} /> : !data ? <Skeleton lines={6} /> : (
          <>
            <Section title={t('branding.names')}>
              <TextField label={t('branding.name')} kind="name" required value={form.name} maxLength={200} editable={data.can_edit}
                onChangeText={(v) => setForm((f) => ({ ...f, name: v }))} testID="branding-name" />
              <TextField label={t('branding.short')} value={form.short} maxLength={40} help={t('branding.shortHelp')} editable={data.can_edit}
                onChangeText={(v) => setForm((f) => ({ ...f, short: v }))} testID="branding-short" />
            </Section>
            <Section title={t('branding.logo')} testID="branding-logo">
              {preview && logo !== 'clear' ? (
                <Image source={{ uri: preview }} style={{ width: 96, height: 96, borderRadius: radius.sm }} contentFit="contain"
                  accessibilityLabel={t('branding.logo')} testID="branding-logo-image" />
              ) : <AppText variant="caption">{t('branding.noLogo')}</AppText>}
              {canPickImage ? (
                <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
                  <Button variant="tonal" icon="upload" label={t('branding.chooseLogo')} disabled={!data.can_edit} loading={busy}
                    onPress={() => void chooseLogo()} testID="branding-logo-choose" />
                  {preview && logo !== 'clear' ? <Button variant="text" icon="delete-outline" label={t('branding.removeLogo')} disabled={!data.can_edit}
                    onPress={() => setLogo('clear')} testID="branding-logo-remove" /> : null}
                </View>
              ) : <AppText variant="caption" testID="branding-logo-web">{t('branding.logoOnWeb')}</AppText>}
              <AppText variant="caption">{t('branding.logoHelp')}</AppText>
            </Section>
            <Section title={t('branding.color')} testID="branding-color">
              <Chips label={t('branding.color')} selected={color ?? ''} onSelect={(v) => setForm((f) => ({ ...f, color: v }))}
                choices={BRAND_PRESETS.map((p) => ({ value: p, label: p, testID: `branding-color-${p.slice(1)}` }))} />
              <TextField label={t('branding.hex')} value={form.color} maxLength={7} editable={data.can_edit} error={color ? null : t('branding.hexInvalid')}
                onChangeText={(v) => setForm((f) => ({ ...f, color: v.trim() }))} testID="branding-hex" />
              {color ? (
                <View style={{ flexDirection: 'row', gap: space.md, alignItems: 'center' }}>
                  <View style={{ width: 40, height: 40, borderRadius: radius.sm, backgroundColor: color }} />
                  <AppText variant="caption" style={{ flex: 1 }} testID="branding-contrast">
                    {[t('branding.contrastLight', { result: light?.usableAsPrimary ? t('branding.contrastOk') : t('branding.contrastAccent') }),
                      t('branding.contrastDark', { result: dark?.usableAsPrimary ? t('branding.contrastOk') : t('branding.contrastAccent') })].join('\n')}
                  </AppText>
                </View>
              ) : null}
            </Section>
            <AppText variant="caption">{t('branding.signInNeutral')}</AppText>
            {data.can_edit ? (
              <Button icon="check" label={t('branding.save')} loading={busy} disabled={form.name.trim().length < 2 || !color}
                onPress={() => void save()} testID="branding-save" />
            ) : <AppText testID="branding-read-only">{t('branding.readOnly')}</AppText>}
          </>
        )}
      </Screen>
    </View>
  );
}
