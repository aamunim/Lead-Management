import { MaterialIcons } from '@expo/vector-icons';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';

import { useTheme } from '../theme';
import type { Temperature } from '../tokens/color';

const ICON = { hot: 'local-fire-department', warm: 'wb-sunny', cold: 'ac-unit' } as const;

// Hot / warm / cold (Ch 47.8): colour + icon + word, never colour alone.
export function TemperatureChip({ temperature, testID }: { temperature: Temperature; testID?: string }) {
  const { colors, radius, space } = useTheme();
  const { t } = useTranslation('ui');
  const word = t(`temperature.${temperature}`);
  const bg = colors[`${temperature}Container`];
  const fg = colors[`on${temperature[0].toUpperCase()}${temperature.slice(1)}Container` as 'onHotContainer'];
  return (
    <View accessibilityLabel={word} accessible testID={testID}
      style={{ flexDirection: 'row', alignItems: 'center', gap: space.xs, alignSelf: 'flex-start', backgroundColor: bg,
        borderRadius: radius.full, paddingHorizontal: space.md, paddingVertical: space.xs, minHeight: 32 }}>
      <MaterialIcons name={ICON[temperature]} size={16} color={fg} />
      <AppText variant="label" style={{ color: fg }}>{word}</AppText>
    </View>
  );
}
