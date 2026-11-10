import { useState, type ComponentRef, type Ref } from 'react';
import { Platform, TextInput, View, type KeyboardTypeOptions, type TextInputProps } from 'react-native';
import { KeyboardController } from 'react-native-keyboard-controller';

import { useTranslation } from '@/i18n';

import { useTheme } from '../theme';

import { IconButton } from './Button';
import { Field, useInputStyle } from './Field';

export type FieldKind = 'text' | 'name' | 'email' | 'number' | 'decimal' | 'password' | 'otp' | 'search' | 'multiline';

type Props = {
  label: string;
  value: string;
  onChangeText: (text: string) => void;
  kind?: FieldKind;
  required?: boolean;
  help?: string;
  error?: string | null;
  placeholder?: string;
  /** Last field of a form: the keyboard shows Done and pressing it runs onDone (usually Save). */
  last?: boolean;
  onDone?: () => void;
  testID?: string;
  ref?: Ref<ComponentRef<typeof TextInput>>;
} & Pick<TextInputProps, 'onBlur' | 'onFocus' | 'maxLength' | 'editable'>;

// The right keyboard for each kind of field (Ch 47.3). Phones and amounts have their own inputs
// (src/components/fields/inputs.tsx) because they also normalise Bangla digits.
const KEYBOARD: Record<FieldKind, Partial<TextInputProps>> = {
  text: { autoCapitalize: 'sentences' },
  name: { autoCapitalize: 'words', autoComplete: 'name', textContentType: 'name' },
  email: { keyboardType: 'email-address' as KeyboardTypeOptions, autoCapitalize: 'none', autoCorrect: false, autoComplete: 'email', textContentType: 'emailAddress', inputMode: 'email' },
  number: { keyboardType: 'number-pad', inputMode: 'numeric' },
  decimal: { keyboardType: 'decimal-pad', inputMode: 'decimal' },
  password: { secureTextEntry: true, autoCapitalize: 'none', autoCorrect: false, autoComplete: 'current-password', textContentType: 'password' },
  // OTP autofill (Ch 10, 47.3): Android reads the SMS code; iOS and the web offer the one-time code.
  otp: { keyboardType: 'number-pad', inputMode: 'numeric', textContentType: 'oneTimeCode',
    autoComplete: Platform.OS === 'android' ? 'sms-otp' : 'one-time-code', maxLength: 8 },
  search: { autoCapitalize: 'none', autoCorrect: false, inputMode: 'search', returnKeyType: 'search' },
  multiline: { multiline: true, autoCapitalize: 'sentences', textAlignVertical: 'top' },
};

// Text field (0A.13-T4): label, error right under the field, the right keyboard, Next moves to the next field and
// Done on the last one submits. Works inside Form / BottomSheet, which keep the focused field above the keyboard.
export function TextField(
  { label, value, onChangeText, kind = 'text', required, help, error, placeholder, last, onDone, testID, ref, ...rest }: Props,
) {
  const { colors, space } = useTheme();
  const { t } = useTranslation('ui');
  const [hidden, setHidden] = useState(true);
  const inputStyle = useInputStyle(!!error);
  const keyboard = KEYBOARD[kind];
  const multiline = kind === 'multiline';
  return (
    <Field label={label} required={required} help={help ?? (kind === 'otp' ? t('form.otpHelp') : undefined)} error={error} testID={testID}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.xs }}>
        <TextInput
          ref={ref}
          {...keyboard}
          {...rest}
          secureTextEntry={kind === 'password' ? hidden : undefined}
          value={value}
          onChangeText={onChangeText}
          placeholder={placeholder}
          placeholderTextColor={colors.onSurfaceVariant}
          accessibilityLabel={label}
          aria-invalid={!!error}
          returnKeyType={multiline ? undefined : (keyboard.returnKeyType ?? (last ? 'done' : 'next'))}
          submitBehavior={multiline ? 'newline' : last ? 'blurAndSubmit' : 'submit'}
          onSubmitEditing={() => {
            if (multiline) return;
            if (last) onDone?.();
            else KeyboardController.setFocusTo('next');
          }}
          style={[inputStyle, { flex: 1 }, multiline ? { minHeight: 112 } : null]}
          testID={testID ? `${testID}-input` : undefined}
        />
        {kind === 'password' ? (
          <IconButton icon={hidden ? 'visibility' : 'visibility-off'} label={hidden ? t('form.showPassword') : t('form.hidePassword')}
            onPress={() => setHidden(!hidden)} />
        ) : null}
      </View>
    </Field>
  );
}
