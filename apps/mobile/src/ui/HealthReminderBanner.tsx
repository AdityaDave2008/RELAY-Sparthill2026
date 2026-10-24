import { type JSX } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';

import { FadeIn } from './transitions';
import { useTheme, useThemedStyles } from './theme';

export function HealthReminderBanner({
  daysSinceUpdate,
  onReview,
  onClose,
}: {
  daysSinceUpdate: number | null;
  /** Omitted when the resident is already on the Health info tab. */
  onReview?: () => void;
  onClose: () => void;
}): JSX.Element {
  const theme = useTheme();
  const styles = useThemedStyles(baseStyles);
  const iconSize = Math.round(22 * theme.scale);

  return (
    <View style={styles.wrap}>
      <FadeIn>
        <View style={styles.banner} accessibilityRole="alert">
          <MaterialCommunityIcons name="bell-ring-outline" size={iconSize} color={theme.color('#92400e')} />
          <View style={styles.body}>
            <Text style={styles.title}>Is your health info still correct?</Text>
            <Text style={styles.text}>
              {daysSinceUpdate === null
                ? 'Please check it so dispatch has the right details.'
                : `Last updated ${daysSinceUpdate} days ago. Please check it so dispatch has the right details.`}
            </Text>
            {onReview && (
              <Pressable style={styles.reviewBtn} onPress={onReview} accessibilityRole="button">
                <Text style={styles.reviewText}>Review health info</Text>
              </Pressable>
            )}
          </View>
          <Pressable
            style={styles.closeBtn}
            onPress={onClose}
            hitSlop={12}
            accessibilityRole="button"
            accessibilityLabel="Close reminder"
          >
            <MaterialCommunityIcons name="close" size={iconSize} color={theme.color('#78350f')} />
          </Pressable>
        </View>
      </FadeIn>
    </View>
  );
}

const baseStyles = StyleSheet.create({
  wrap: { paddingHorizontal: 12, paddingTop: 8 },
  banner: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 10,
    padding: 12,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#f59e0b',
    backgroundColor: '#fef3c7',
  },
  body: { flex: 1, gap: 4 },
  title: { fontSize: 16, fontWeight: '800', color: '#78350f' },
  text: { fontSize: 14, lineHeight: 20, color: '#78350f' },
  reviewBtn: {
    alignSelf: 'flex-start',
    marginTop: 6,
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 8,
    backgroundColor: '#92400e',
  },
  reviewText: { fontSize: 14, fontWeight: '700', color: 'white' },
  closeBtn: { padding: 2 },
});
