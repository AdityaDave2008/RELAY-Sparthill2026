import { type JSX, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Keyboard, Pressable, StyleSheet, Text, View } from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';

import { configureAmplify, isAuthConfigured } from './config/amplify';
import { isHealthComplete, summarizeHealth, useHealthProfile } from './relay/health';
import { HealthScreen } from './screens/HealthScreen';
import { ResidentScreen } from './screens/ResidentScreen';
import { SettingsScreen } from './screens/SettingsScreen';
import { TextSizeScreen } from './screens/TextSizeScreen';
import { SettingsProvider, useSettings, useThemedStyles } from './ui/theme';
import { FadeIn, TabScene } from './ui/transitions';
import { HealthReminderBanner } from './ui/HealthReminderBanner';
import { useHealthReminder } from './relay/healthReminder';

type Tab = 'help' | 'health' | 'settings';

const TABS: {
  id: Tab;
  label: string;
  icon: keyof typeof MaterialCommunityIcons.glyphMap;
}[] = [
  { id: 'help', label: 'Ask for help', icon: 'lifebuoy' },
  { id: 'health', label: 'Health info', icon: 'heart-pulse' },
  { id: 'settings', label: 'Settings', icon: 'cog' },
];

/**
 * Root component.
 *
 * Auth is handled by Amplify UI's <Authenticator> (Amazon Cognito) ONLY when a
 * Cognito pool is configured via EXPO_PUBLIC_COGNITO_* env vars. For offline/
 * local demos with no pool, the app runs without the auth gate and talks to the
 * RELAY REST API using the shared demo bearer token (EXPO_PUBLIC_DEVICE_TOKEN).
 *
 * The RELAY backend is NOT an Amplify-provisioned backend — Amplify is used
 * here purely for the client-side auth UI.
 */
export default function App(): JSX.Element {
  const [authReady, setAuthReady] = useState(false);

  useEffect(() => {
    configureAmplify();
    setAuthReady(true);
  }, []);

  if (!authReady) return <SafeAreaProvider />;

  const content = (
    <SafeAreaProvider>
      <SettingsProvider>
        <SafeAreaView style={{ flex: 1 }}>
          <StatusBar style="auto" />
          <Tabs />
        </SafeAreaView>
      </SettingsProvider>
    </SafeAreaProvider>
  );

  if (!isAuthConfigured()) {
    // No Cognito pool: skip the auth gate for local/offline demos.
    return content;
  }

  return <AuthenticatedApp>{content}</AuthenticatedApp>;
}

/**
 * All screens stay mounted so the help form keeps its draft and background
 * sync keeps running while the resident uses another tab.
 */
function Tabs(): JSX.Element {
  const [{ tab, direction }, setNav] = useState<{ tab: Tab; direction: number }>({
    tab: 'help',
    direction: 1,
  });
  const index = (id: Tab) => TABS.findIndex((t) => t.id === id);
  const setTab = (next: Tab) => {
    if (next === tab) return;
    Keyboard.dismiss();
    setNav({ tab: next, direction: Math.sign(index(next) - index(tab)) || 1 });
  };
  const health = useHealthProfile();
  const settings = useSettings();
  const styles = useThemedStyles(baseStyles);
  const { theme } = settings;
  const healthSummary = useMemo(() => summarizeHealth(health.profile), [health.profile]);
  const complete = useMemo(() => isHealthComplete(health.profile), [health.profile]);
  const reminder = useHealthReminder(health.profile.updatedAt, settings.settings.healthReminder);

  // Wait for saved settings too, so the first screen doesn't flash at the wrong size.
  if (!health.ready || !settings.ready) {
    return (
      <View style={[styles.root, styles.center]}>
        <ActivityIndicator />
      </View>
    );
  }

  // First run: choose a readable text size before the health form. Residents
  // who already finished the health form are not sent back here.
  if (!complete && !settings.settings.textSizeChosen) {
    return (
      <View style={styles.root}>
        <FadeIn key="text-size">
          <TextSizeScreen onContinue={() => settings.update({ textSizeChosen: true })} />
        </FadeIn>
      </View>
    );
  }

  // Health info must be complete before the main screen; clearing it returns here.
  if (!complete) {
    return (
      <View style={styles.root}>
        <FadeIn key="onboarding">
          <HealthScreen
            mode="onboarding"
            ready={health.ready}
            profile={health.profile}
            loadError={health.error}
            onSave={async (next) => {
              Keyboard.dismiss();
              await health.save(next);
              setNav({ tab: 'help', direction: 1 });
            }}
          />
        </FadeIn>
      </View>
    );
  }

  return (
    <View style={styles.root}>
      <FadeIn key="main">
        {reminder.due && (
          <HealthReminderBanner
            daysSinceUpdate={reminder.daysSinceUpdate}
            onReview={tab === 'health' ? undefined : () => setTab('health')}
            onClose={reminder.dismiss}
          />
        )}
        <View style={styles.screen}>
          <TabScene active={tab === 'help'} direction={direction}>
            <ResidentScreen healthSummary={healthSummary} />
          </TabScene>
          <TabScene active={tab === 'health'} direction={direction}>
            <HealthScreen
              mode="edit"
              ready={health.ready}
              profile={health.profile}
              loadError={health.error}
              onSave={health.save}
              onClear={health.clear}
              reminderDue={reminder.due}
            />
          </TabScene>
          <TabScene active={tab === 'settings'} direction={direction}>
            <SettingsScreen />
          </TabScene>
        </View>
        <View style={styles.tabBar} accessibilityRole="tablist">
          {TABS.map((t) => {
            const selected = tab === t.id;
            return (
              <Pressable
                key={t.id}
                style={[styles.tab, selected && styles.tabSelected]}
                onPress={() => setTab(t.id)}
                accessibilityRole="tab"
                accessibilityState={{ selected }}
                accessibilityLabel={t.label}
              >
                <MaterialCommunityIcons
                  name={t.icon}
                  size={Math.round(24 * theme.scale)}
                  color={theme.color(selected ? '#ea580c' : '#64748b')}
                />
                <Text
                  style={[styles.tabLabel, selected ? styles.tabLabelActive : styles.tabInactive]}
                  numberOfLines={2}
                >
                  {t.label}
                </Text>
              </Pressable>
            );
          })}
        </View>
      </FadeIn>
    </View>
  );
}

/**
 * Wraps the app in Amplify UI's Authenticator. Imported lazily so the Amplify UI
 * native dependency is only required when auth is actually configured.
 */
function AuthenticatedApp({ children }: { children: JSX.Element }): JSX.Element {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { Authenticator } = require('@aws-amplify/ui-react-native');
  return (
    <Authenticator.Provider>
      <Authenticator>{children}</Authenticator>
    </Authenticator.Provider>
  );
}

const baseStyles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#f8fafc' },
  center: { alignItems: 'center', justifyContent: 'center' },
  // Scenes are layered inside this box; clip them so slides don't overlap the tab bar.
  screen: { flex: 1, overflow: 'hidden' },
  tabBar: {
    flexDirection: 'row',
    borderTopWidth: 1,
    borderTopColor: '#e2e8f0',
    backgroundColor: 'white',
  },
  // Selected tab gets a top bar so it stays distinguishable without relying on colour.
  tab: { flex: 1, alignItems: 'center', paddingVertical: 10, gap: 2, borderTopWidth: 3, borderTopColor: 'transparent' },
  tabSelected: { borderTopColor: '#ea580c' },
  tabLabel: { fontSize: 13, fontWeight: '600', textAlign: 'center' },
  tabLabelActive: { color: '#ea580c', fontWeight: '800' },
  tabInactive: { color: '#64748b' },
});
