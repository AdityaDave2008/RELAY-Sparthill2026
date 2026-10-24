import { type JSX, useEffect, useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';

import { configureAmplify, isAuthConfigured } from './config/amplify';
import { summarizeHealth, useHealthProfile } from './relay/health';
import { HealthScreen } from './screens/HealthScreen';
import { ResidentScreen } from './screens/ResidentScreen';

type Tab = 'help' | 'health';

const TABS: { id: Tab; label: string; glyph: string }[] = [
  { id: 'help', label: 'Ask for help', glyph: '🆘' },
  { id: 'health', label: 'Health info', glyph: '✚' },
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
      <SafeAreaView style={{ flex: 1 }}>
        <StatusBar style="auto" />
        <Tabs />
      </SafeAreaView>
    </SafeAreaProvider>
  );

  if (!isAuthConfigured()) {
    // No Cognito pool: skip the auth gate for local/offline demos.
    return content;
  }

  return <AuthenticatedApp>{content}</AuthenticatedApp>;
}

/**
 * Both screens stay mounted so the help form keeps its draft and background
 * sync keeps running while the resident edits health info.
 */
function Tabs(): JSX.Element {
  const [tab, setTab] = useState<Tab>('help');
  const health = useHealthProfile();
  const healthSummary = useMemo(() => summarizeHealth(health.profile), [health.profile]);

  return (
    <View style={styles.root}>
      <View style={[styles.screen, tab !== 'help' && styles.hidden]}>
        <ResidentScreen healthSummary={healthSummary} onEditHealth={() => setTab('health')} />
      </View>
      <View style={[styles.screen, tab !== 'health' && styles.hidden]}>
        <HealthScreen
          ready={health.ready}
          profile={health.profile}
          loadError={health.error}
          onSave={health.save}
          onClear={health.clear}
        />
      </View>
      <View style={styles.tabBar} accessibilityRole="tablist">
        {TABS.map((t) => {
          const selected = tab === t.id;
          return (
            <Pressable
              key={t.id}
              style={styles.tab}
              onPress={() => setTab(t.id)}
              accessibilityRole="tab"
              accessibilityState={{ selected }}
            >
              <Text style={[styles.tabGlyph, !selected && styles.tabInactive]}>{t.glyph}</Text>
              <Text style={[styles.tabLabel, selected ? styles.tabLabelActive : styles.tabInactive]}>
                {t.label}
              </Text>
            </Pressable>
          );
        })}
      </View>
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

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#f8fafc' },
  screen: { flex: 1 },
  hidden: { display: 'none' },
  tabBar: {
    flexDirection: 'row',
    borderTopWidth: 1,
    borderTopColor: '#e2e8f0',
    backgroundColor: 'white',
  },
  tab: { flex: 1, alignItems: 'center', paddingVertical: 10, gap: 2 },
  tabGlyph: { fontSize: 20 },
  tabLabel: { fontSize: 13, fontWeight: '600' },
  tabLabelActive: { color: '#ea580c' },
  tabInactive: { color: '#64748b', opacity: 0.7 },
});
