import { MaterialIcons } from '@expo/vector-icons';
import { Pressable, View } from 'react-native';

import { AppText } from '@/components/AppText';

import { useTheme } from '../theme';

export type Choice<T> = { value: T; label: string; testID?: string };

// One-of-many choice (radio list): 48 dp rows, selection shown by icon and border (not colour alone).
export function ChoiceList<T>({ choices, selected, onSelect, accessibilityLabel }: {
  choices: Choice<T>[]; selected: T; onSelect: (value: T) => void; accessibilityLabel: string;
}) {
  const { colors, radius, space, touch } = useTheme();
  return (
    <View accessibilityRole="radiogroup" accessibilityLabel={accessibilityLabel} style={{ gap: space.sm }}>
      {choices.map((choice) => {
        const on = choice.value === selected;
        return (
          <Pressable
            key={String(choice.value)}
            accessibilityRole="radio"
            accessibilityState={{ selected: on, checked: on }}
            accessibilityLabel={choice.label}
            onPress={() => onSelect(choice.value)}
            testID={choice.testID}
            style={({ pressed }) => ({
              minHeight: touch, flexDirection: 'row', alignItems: 'center', gap: space.md, paddingHorizontal: space.lg, paddingVertical: space.sm,
              borderRadius: radius.md, borderWidth: on ? 2 : 1, borderColor: on ? colors.primary : colors.outlineVariant,
              backgroundColor: on ? colors.primaryContainer : colors.surfaceContainerLow, opacity: pressed ? 0.85 : 1,
            })}
          >
            <MaterialIcons name={on ? 'radio-button-checked' : 'radio-button-unchecked'} size={22}
              color={on ? colors.onPrimaryContainer : colors.onSurfaceVariant} />
            <AppText style={{ flex: 1, color: on ? colors.onPrimaryContainer : colors.onSurface }}>{choice.label}</AppText>
          </Pressable>
        );
      })}
    </View>
  );
}
