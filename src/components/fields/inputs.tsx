import { useState } from 'react';
import { TextInput } from 'react-native';
import { KeyboardController } from 'react-native-keyboard-controller';

import { cleanNumberTyping, cleanPhoneTyping, isValidPhone, normalizePhone, parseNumberInput } from '@/lib/format';
import { useFormat } from '@/lib/locale';
import { Field, useInputStyle } from '@/ui/components/Field';
import { useTheme } from '@/ui/theme';

type FieldProps<T> = {
  label: string;
  value: T | null;
  onChange: (value: T | null) => void;
  help?: string;
  errorText?: string;
  testID?: string;
  required?: boolean;
  /** Last field of a form: Done instead of Next. */
  last?: boolean;
  onDone?: () => void;
};

const nextOrDone = (last?: boolean, onDone?: () => void) => () => {
  if (last) onDone?.();
  else KeyboardController.setFocusTo('next');
};

/**
 * Phone field (0A.11-T3): Bangla digits become ASCII as they are typed or pasted; on leaving the field the number is
 * normalised with the institution's rules (country code, spaces, dashes). The value given to the form is the normalised one.
 * The server normalises again (never trust the client alone).
 */
export function PhoneInput({ label, value, onChange, help, errorText, testID, required, last, onDone }: FieldProps<string>) {
  const { locale } = useFormat();
  const { colors } = useTheme();
  const [text, setText] = useState(value ?? '');
  const normalized = locale ? normalizePhone(text, locale.phone) : null;
  const invalid = text.trim() !== '' && locale !== null && !isValidPhone(normalized, locale.phone);
  const inputStyle = useInputStyle(invalid);
  return (
    <Field label={label} required={required} help={help} error={invalid ? errorText : null}>
      <TextInput
        testID={testID}
        style={inputStyle}
        value={text}
        accessibilityLabel={label}
        keyboardType="phone-pad"
        autoComplete="tel"
        textContentType="telephoneNumber"
        inputMode="tel"
        returnKeyType={last ? 'done' : 'next'}
        submitBehavior={last ? 'blurAndSubmit' : 'submit'}
        onSubmitEditing={nextOrDone(last, onDone)}
        placeholder={locale?.phone.example}
        placeholderTextColor={colors.onSurfaceVariant}
        onChangeText={(next) => {
          const cleaned = cleanPhoneTyping(next);
          setText(cleaned);
          onChange(locale ? normalizePhone(cleaned, locale.phone) : null);
        }}
        onBlur={() => {
          if (normalized) setText(normalized);
        }}
      />
    </Field>
  );
}

/**
 * Amount field (0A.11-T3/T4): accepts Bangla digits and lakh grouping; shows the amount formatted (lakh style,
 * currency, digits per setting) when not editing; gives the form a canonical ASCII string ("150000.50").
 */
export function AmountInput({ label, value, onChange, help, errorText, testID, required, last, onDone }: FieldProps<string>) {
  const format = useFormat();
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(value ?? '');
  const decimals = (format.locale?.currency.decimals ?? 0) > 0;
  const parsed = parseNumberInput(text);
  const invalid = text.trim() !== '' && parsed === null;
  const inputStyle = useInputStyle(invalid);
  return (
    <Field label={label} required={required} help={help} error={invalid ? errorText : null}>
      <TextInput
        testID={testID}
        style={inputStyle}
        accessibilityLabel={label}
        value={editing || invalid || parsed === null ? text : format.money(parsed)}
        keyboardType={decimals ? 'decimal-pad' : 'number-pad'}
        inputMode={decimals ? 'decimal' : 'numeric'}
        returnKeyType={last ? 'done' : 'next'}
        submitBehavior={last ? 'blurAndSubmit' : 'submit'}
        onSubmitEditing={nextOrDone(last, onDone)}
        onFocus={() => setEditing(true)}
        onBlur={() => setEditing(false)}
        onChangeText={(next) => {
          const cleaned = cleanNumberTyping(next, decimals);
          setText(cleaned);
          onChange(parseNumberInput(cleaned));
        }}
      />
    </Field>
  );
}
