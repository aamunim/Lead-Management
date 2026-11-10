import { useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

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
    <View style={styles.container} testID={testID}>
      <Text style={styles.title}>{labels.title}</Text>
      <View style={styles.row}>
        <Text style={styles.hint} testID={testID ? `${testID}-hint` : undefined} selectable={false}>
          {shownHint ?? labels.notSet}
        </Text>
        {validFrom ? <Text style={styles.meta}>{validFrom}</Text> : null}
        {!editing && (
          <Pressable style={styles.button} onPress={() => setEditing(true)} accessibilityRole="button">
            <Text>{labels.replace}</Text>
          </Pressable>
        )}
      </View>
      {editing && (
        <View style={styles.editor}>
          <TextInput
            style={styles.input}
            value={value}
            onChangeText={setValue}
            placeholder={labels.newValuePlaceholder}
            secureTextEntry
            autoCapitalize="none"
            autoCorrect={false}
            autoComplete="off"
            textContentType="none"
            importantForAutofill="no"
          />
          <TextInput
            style={styles.input}
            value={activeFrom}
            onChangeText={setActiveFrom}
            placeholder={labels.activeFromPlaceholder}
            autoCapitalize="none"
          />
          <View style={styles.row}>
            <Pressable style={styles.button} onPress={save} disabled={busy || value.length === 0} accessibilityRole="button">
              {busy ? <ActivityIndicator /> : <Text>{labels.save}</Text>}
            </Pressable>
            <Pressable style={styles.button} onPress={close} accessibilityRole="button">
              <Text>{labels.cancel}</Text>
            </Pressable>
          </View>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { gap: 8 },
  title: { fontWeight: '600' },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, flexWrap: 'wrap' },
  hint: { fontFamily: 'monospace' },
  meta: { opacity: 0.7 },
  editor: { gap: 8 },
  input: { borderWidth: 1, borderColor: '#999', borderRadius: 8, padding: 12, minHeight: 48 },
  button: { borderWidth: 1, borderColor: '#999', borderRadius: 8, paddingHorizontal: 16, minHeight: 48, justifyContent: 'center' },
});
