import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { fetchModules, setModule, type ModuleState } from '@/lib/modules';
import { loadSettings } from '@/lib/settings';
import { Badge, CheckRow } from '@/ui/admin/parts';
import { BottomSheet, Button, ErrorState, Screen, Skeleton, useSnackbar } from '@/ui/components';
import { moduleName } from '@/ui/limits/names';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Settings → Modules (0B.05-T2, T3; Ch 9.2): turn on or off the modules the plan allows. Turning one off removes it
// from menus, Home, filters, reports and settings and pauses its jobs; its data is kept and returns when it is on
// again. Before a change the impact is shown (what it needs, what else stops). Core leads and follow-ups are always on.
export default function ModulesScreen() {
  const { t } = useTranslation('admin');
  const { colors, space } = useTheme();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [mods, setMods] = useState<ModuleState[] | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [change, setChange] = useState<{ module: ModuleState; enabled: boolean; stops: string[] } | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    const r = await fetchModules();
    if (r.error) setError(r.error);
    else setMods(r.data ?? []);
  }, []);
  useEffect(() => {
    void load();
  }, [load]);

  const ask = async (m: ModuleState) => {
    const enabled = !m.switched_on;
    const r = await setModule(m.key, enabled, false);
    if (r.error || !r.data) return snackbar.show({ text: r.error ? errorText(r.error).message : '' });
    setChange({ module: m, enabled, stops: r.data.impact.stops });
  };
  const apply = async () => {
    if (!change) return;
    setBusy(true);
    const r = await setModule(change.module.key, change.enabled, true);
    setBusy(false);
    if (r.error) return snackbar.show({ text: errorText(r.error).message });
    await loadSettings(true);
    snackbar.show({ text: change.enabled ? t('modules.turnedOn') : t('modules.turnedOff') });
    setChange(null);
    void load();
  };
  const nameOf = (key: string) => moduleName(mods?.find((m) => m.key === key) ?? { key, label_key: null });
  const shown = (mods ?? []).filter((m) => m.in_industry);

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('modules.title')} intro={t('modules.intro')} testID="modules">
        {error ? <ErrorState error={error} onRetry={() => void load()} testID="modules-error" /> : !mods ? <Skeleton lines={8} testID="modules-loading" /> : (
          <View style={{ gap: space.xs }}>
            {shown.map((m) => (
              <CheckRow key={m.key} label={moduleName(m)} checked={m.enabled} disabled={m.always_on || !m.allowed}
                onToggle={() => void ask(m)} testID={`module-${m.key}`}
                help={m.depends_on.length ? t('modules.needs', { names: m.depends_on.map(nameOf).join(', ') }) : undefined}
                badge={m.always_on ? <Badge label={t('modules.alwaysOn')} icon="lock" />
                  : !m.allowed ? <Badge label={t('modules.notInPlan')} tone="warning" />
                    : m.switched_on && !m.enabled ? <Badge label={t('modules.waiting')} tone="warning" /> : undefined} />
            ))}
          </View>
        )}
      </Screen>
      {change ? (
        <BottomSheet visible onClose={() => setChange(null)} testID="module-sheet"
          title={change.enabled ? t('modules.onTitle', { name: moduleName(change.module) }) : t('modules.offTitle', { name: moduleName(change.module) })}
          footer={<Button variant={change.enabled ? 'filled' : 'danger'} label={change.enabled ? t('modules.turnOn') : t('modules.turnOff')}
            loading={busy} fullWidth onPress={() => void apply()} testID="module-confirm" />}>
          <AppText>{change.enabled ? t('modules.onBody') : t('modules.offBody')}</AppText>
          {change.stops.length ? (
            <AppText style={{ color: colors.error }} testID="module-stops">{t('modules.alsoStops', { names: change.stops.map(nameOf).join(', ') })}</AppText>
          ) : null}
        </BottomSheet>
      ) : null}
    </View>
  );
}
