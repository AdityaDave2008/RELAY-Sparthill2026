import { type JSX } from 'react';
import { Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';

import { TEXT_SCALE, type TextSize, useSettings, useThemedStyles } from '../ui/theme';

const SIZES: { id: TextSize; label: string }[] = [
  { id: 'normal', label: 'Normal' },
  { id: 'large', label: 'Large' },
  { id: 'largest', label: 'Largest' },
];

export function SettingsScreen(): JSX.Element {
  const { settings, update, error } = useSettings();
  const styles = useThemedStyles(baseStyles);

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.title}>Settings</Text>

      {error && (
        <View style={styles.errorBanner}>
          <Text style={styles.errorText}>{error}</Text>
        </View>
      )}

      <Text style={styles.sectionTitle}>Text size</Text>
      <TextSizePicker />

      <ToggleCard
        title="High contrast"
        subtitle="Black text on white, thicker lines"
        value={settings.highContrast}
        onChange={(highContrast) => update({ highContrast })}
      />

      <Text style={styles.sectionTitle}>Reminders</Text>
      <ToggleCard
        title="Health info reminder"
        subtitle="Every 2 weeks, show a yellow banner asking you to check your health info"
        value={settings.healthReminder}
        onChange={(healthReminder) => update({ healthReminder })}
      />
    </ScrollView>
  );
}

/** Normal / Large / Largest cards. Also used on the first-run text size page. */
export function TextSizePicker(): JSX.Element {
  const { settings, update } = useSettings();
  const styles = useThemedStyles(baseStyles);
  return (
    <View style={styles.sizes} accessibilityRole="radiogroup">
      {SIZES.map((size) => {
        const selected = settings.textSize === size.id;
        return (
          <Pressable
            key={size.id}
            style={[styles.sizeCard, selected && styles.sizeCardSelected]}
            onPress={() => update({ textSize: size.id })}
            accessibilityRole="radio"
            accessibilityState={{ checked: selected }}
            accessibilityLabel={`${size.label} text`}
          >
            {/* The sample shows each size relative to the current one, so it is not double-scaled. */}
            <Text style={[styles.sample, { fontSize: Math.round(26 * TEXT_SCALE[size.id]) }]}>Aa</Text>
            <Text style={styles.sizeLabel}>{size.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

function ToggleCard({
  title,
  subtitle,
  value,
  onChange,
}: {
  title: string;
  subtitle: string;
  value: boolean;
  onChange: (value: boolean) => void;
}): JSX.Element {
  const { theme } = useSettings();
  const styles = useThemedStyles(baseStyles);
  return (
    <Pressable
      style={styles.toggleCard}
      onPress={() => onChange(!value)}
      accessibilityRole="switch"
      accessibilityState={{ checked: value }}
      accessibilityLabel={title}
      accessibilityHint={subtitle}
    >
      <View style={styles.toggleText}>
        <Text style={styles.toggleTitle}>{title}</Text>
        <Text style={styles.toggleSubtitle}>{subtitle}</Text>
      </View>
      <Switch
        value={value}
        onValueChange={onChange}
        trackColor={{ false: '#9ca3af', true: theme.highContrast ? '#000000' : '#0f172a' }}
        thumbColor="#ffffff"
        ios_backgroundColor="#9ca3af"
        accessibilityElementsHidden
        importantForAccessibility="no"
      />
    </Pressable>
  );
}

const baseStyles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f8fafc' },
  content: { padding: 20, gap: 16, paddingBottom: 40 },
  title: { fontSize: 30, fontWeight: '800', color: '#0f172a' },
  sectionTitle: { fontSize: 20, fontWeight: '800', color: '#0f172a', marginTop: 4 },
  errorBanner: { borderRadius: 10, backgroundColor: '#fef2f2', borderWidth: 1, borderColor: '#fecaca', padding: 12 },
  errorText: { color: '#991b1b', fontSize: 14, lineHeight: 20 },
  sizes: { flexDirection: 'row', gap: 10 },
  sizeCard: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    minHeight: 104,
    paddingVertical: 12,
    paddingHorizontal: 6,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#94a3b8',
    backgroundColor: 'white',
  },
  sizeCardSelected: { borderWidth: 3, borderColor: '#0f172a', backgroundColor: '#fff0e6' },
  sample: { fontWeight: '800', color: '#0f172a' },
  sizeLabel: { fontSize: 16, fontWeight: '700', color: '#0f172a' },
  toggleCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    padding: 16,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#94a3b8',
    backgroundColor: 'white',
  },
  toggleText: { flex: 1, gap: 4 },
  toggleTitle: { fontSize: 17, fontWeight: '800', color: '#0f172a' },
  toggleSubtitle: { fontSize: 15, color: '#475569' },
});
