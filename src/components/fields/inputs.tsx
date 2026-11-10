import { useState } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useColors } from '@/components/theme';
import { fontFamilyFor } from '@/i18n/language';
import { cleanNumberTyping, cleanPhoneTyping, isValidPhone, normalizePhone, parseNumberInput } from '@/lib/format';
import { useLanguageState } from '@/lib/language';
import { useFormat } from '@/lib/locale';

type FieldProps<T> = {
  label: string;
  value: T | null;
  onChange: (value: T | null) => void;
  help?: string;
  errorText?: string;
  testID?: string;
};

function useInputStyle() {
  const colors = useColors();
  const { language } = useLanguageState();
  const fontFamily = fontFamilyFor(language);
  return [styles.input, { color: colors.text, borderColor: colors.border, backgroundColor: colors.surface }, fontFamily ? { fontFamily } : null];
}

/**
 * Phone field (0A.11-T3): Bangla digits become ASCII as they are typed or pasted; on leaving the field the number is
 * normalised with the institution's rules (+880, spaces, dashes). The value given to the form is the normalised one.
 * The server normalises again (never trust the client alone).
 */
export function PhoneInput({ label, value, onChange, help, errorText, testID }: FieldProps<string>) {
  const { locale } = useFormat();
  const colors = useColors();
  const inputStyle = useInputStyle();
  const [text, setText] = useState(value ?? '');
  const normalized = locale ? normalizePhone(text, locale.phone) : null;
  const invalid = text.trim() !== '' && locale !== null && !isValidPhone(normalized, locale.phone);
  return (
    <View style={styles.field}>
      <AppText style={styles.label}>{label}</AppText>
      <TextInput
        testID={testID}
        style={inputStyle}
        value={text}
        keyboardType="phone-pad"
        autoComplete="tel"
        inputMode="tel"
        placeholder={locale?.phone.example}
        placeholderTextColor={colors.muted}
        onChangeText={(next) => {
          const cleaned = cleanPhoneTyping(next);
          setText(cleaned);
          onChange(locale ? normalizePhone(cleaned, locale.phone) : null);
        }}
        onBlur={() => {
          if (normalized) setText(normalized);
        }}
      />
      {invalid && errorText ? <AppText style={[styles.help, { color: colors.danger }]}>{errorText}</AppText> : null}
      {!invalid && help ? <AppText style={[styles.help, { color: colors.muted }]}>{help}</AppText> : null}
    </View>
  );
}

/**
 * Amount field (0A.11-T3/T4): accepts Bangla digits and lakh grouping; shows the amount formatted (lakh style,
 * currency, digits per setting) when not editing; gives the form a canonical ASCII string ("150000.50").
 */
export function AmountInput({ label, value, onChange, help, errorText, testID }: FieldProps<string>) {
  const format = useFormat();
  const colors = useColors();
  const inputStyle = useInputStyle();
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(value ?? '');
  const decimals = (format.locale?.currency.decimals ?? 0) > 0;
  const parsed = parseNumberInput(text);
  const invalid = text.trim() !== '' && parsed === null;
  return (
    <View style={styles.field}>
      <AppText style={styles.label}>{label}</AppText>
      <TextInput
        testID={testID}
        style={inputStyle}
        value={editing || invalid || parsed === null ? text : format.money(parsed)}
        keyboardType={decimals ? 'decimal-pad' : 'number-pad'}
        inputMode={decimals ? 'decimal' : 'numeric'}
        onFocus={() => setEditing(true)}
        onBlur={() => setEditing(false)}
        onChangeText={(next) => {
          const cleaned = cleanNumberTyping(next, decimals);
          setText(cleaned);
          onChange(parseNumberInput(cleaned));
        }}
      />
      {invalid && errorText ? <AppText style={[styles.help, { color: colors.danger }]}>{errorText}</AppText> : null}
      {!invalid && help ? <AppText style={[styles.help, { color: colors.muted }]}>{help}</AppText> : null}
    </View>
  );
}

export const styles = StyleSheet.create({
  field: { gap: 6 },
  label: { fontSize: 14, fontWeight: '600' },
  input: { minHeight: 48, borderWidth: 1, borderRadius: 8, paddingHorizontal: 12, fontSize: 16 },
  help: { fontSize: 13 },
});
