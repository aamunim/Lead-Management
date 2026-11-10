import { useState } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { Button } from '@/ui/components/Button';
import { useInputStyle } from '@/ui/components/Field';
import { useTheme } from '@/ui/theme';

// Secret field (0A.07-T5): shows ONLY the hint (e.g. "sk-l…9911"), never the value. Replacing writes a new value
// through `secret_set` (write-only); an optional "active from" date makes it a rotation (the old value keeps working
// until then). All visible words come from the caller (translations arrive in 0A.10) — none are hard-coded here.

export type SecretFieldLabels = {
  title: string;
  notSet: string;
  replace: string;
  save: string;
  cancel: string;
  newValuePlaceholder: string;
  activeFromPlaceholder: string; // e.g. "YYYY-MM-DD (empty = now)"
};

export type SecretFieldProps = {
  labels: SecretFieldLabels;
  hint: string | null;
  validFrom?: string | null;
  /** Writes the value; must resolve to the new hint. The value is dropped from memory right after. */
  onSave: (value: string, activeFrom: string | null) => Promise<string>;
  onError?: (error: unknown) => void;
  testID?: string;
};

export function SecretField({ labels, hint, validFrom, onSave, onError, testID }: SecretFieldProps) {
  const [editing, setEditing] = useState(false);
  const [value, setValue] = useState('');
  const [activeFrom, setActiveFrom] = useState('');
  const [busy, setBusy] = useState(false);
  const [shownHint, setShownHint] = useState(hint);
  const { colors, space } = useTheme();
  const inputStyle = useInputStyle();

  const close = () => {
    setValue('');
    setActiveFrom('');
    setEditing(false);
  };

  const save = async () => {
    if (busy || value.length === 0) return;
    setBusy(true);
    try {
      setShownHint(await onSave(value, activeFrom.trim() || null));
      close();
    } catch (error) {
      onError?.(error);
    } finally {
      setBusy(false);
    }
  };

  return (
    <View style={{ gap: space.sm }} testID={testID}>
      <AppText variant="label">{labels.title}</AppText>
      <View style={[styles.row, { gap: space.md }]}>
        <AppText style={styles.hint} testID={testID ? `${testID}-hint` : undefined} selectable={false}>
          {shownHint ?? labels.notSet}
        </AppText>
        {validFrom ? <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{validFrom}</AppText> : null}
        {!editing && <Button variant="outlined" label={labels.replace} onPress={() => setEditing(true)} />}
      </View>
      {editing && (
        <View style={{ gap: space.sm }}>
          <TextInput
            style={inputStyle}
            value={value}
            onChangeText={setValue}
            placeholder={labels.newValuePlaceholder}
            placeholderTextColor={colors.onSurfaceVariant}
            accessibilityLabel={labels.newValuePlaceholder}
            secureTextEntry
            autoCapitalize="none"
            autoCorrect={false}
            autoComplete="off"
            textContentType="none"
            importantForAutofill="no"
          />
          <TextInput
            style={inputStyle}
            value={activeFrom}
            onChangeText={setActiveFrom}
            placeholder={labels.activeFromPlaceholder}
            placeholderTextColor={colors.onSurfaceVariant}
            accessibilityLabel={labels.activeFromPlaceholder}
            autoCapitalize="none"
          />
          <View style={[styles.row, { gap: space.md }]}>
            <Button label={labels.save} onPress={() => void save()} loading={busy} disabled={value.length === 0} />
            <Button variant="text" label={labels.cancel} onPress={close} />
          </View>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap' },
  hint: { fontFamily: 'monospace' },
});
