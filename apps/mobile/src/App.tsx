import { type JSX, useEffect, useState } from 'react';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';

import { configureAmplify, isAuthConfigured } from './config/amplify';
import { ResidentScreen } from './screens/ResidentScreen';

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
        <ResidentScreen />
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
