import Constants from 'expo-constants';
import { StyleSheet, Text, View } from 'react-native';

// Placeholder route for milestone 0A.01 ("the app boots").
// No user-facing words are hard-coded: the only text shown is the product
// name from app config. Real screens use translations + labels (0A.10, 0A.12).
export default function PlaceholderScreen() {
  const productName = Constants.expoConfig?.name ?? '';
  return (
    <View style={styles.container} testID="placeholder-root">
      <Text style={styles.title}>{productName}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 16 },
  title: { fontSize: 20, fontWeight: '600' },
});
