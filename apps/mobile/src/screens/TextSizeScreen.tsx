import { type JSX } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { useThemedStyles } from '../ui/theme';
import { TextSizePicker } from './SettingsScreen';

/**
 * First-run page, shown before the health form, so the resident can make the
 * text readable before filling anything in. The choice applies immediately.
 */
export function TextSizeScreen({ onContinue }: { onContinue: () => void }): JSX.Element {
  const styles = useThemedStyles(baseStyles);

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <View style={styles.headerBlock}>
        <Text style={styles.title}>Choose your text size</Text>
        <Text style={styles.subtitle}>
          Pick the size that is easiest for you to read. You can change it later in Settings.
        </Text>
      </View>

      <TextSizePicker />

      <View style={styles.preview} accessibilityLabel="Preview">
        <Text style={styles.previewLabel}>PREVIEW</Text>
        <Text style={styles.previewTitle}>Ask for help</Text>
        <Text style={styles.previewBody}>
          Works without signal. Your request is stored on this phone and sent when this phone
          reconnects.
        </Text>
      </View>

      <Pressable style={styles.continueBtn} onPress={onContinue} accessibilityRole="button">
        <Text style={styles.continueText}>Continue</Text>
      </Pressable>
    </ScrollView>
  );
}

const baseStyles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f8fafc' },
  content: { padding: 20, gap: 20, paddingBottom: 40 },
  headerBlock: { gap: 6 },
  title: { fontSize: 30, fontWeight: '800', color: '#0f172a' },
  subtitle: { fontSize: 16, color: '#475569', lineHeight: 22 },
  preview: { gap: 6, padding: 16, borderRadius: 12, borderWidth: 1, borderColor: '#cbd5e1', backgroundColor: 'white' },
  previewLabel: { fontSize: 12, fontWeight: '800', color: '#64748b' },
  previewTitle: { fontSize: 22, fontWeight: '800', color: '#0f172a' },
  previewBody: { fontSize: 16, lineHeight: 22, color: '#475569' },
  continueBtn: { backgroundColor: '#0f172a', paddingVertical: 16, borderRadius: 12, alignItems: 'center' },
  continueText: { color: 'white', fontSize: 17, fontWeight: '700' },
});
