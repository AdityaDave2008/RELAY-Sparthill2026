import { Amplify } from 'aws-amplify';

/**
 * Amplify client configuration for the RELAY mobile app.
 *
 * RELAY's backend is the hand-written REST API in `services/api` (DynamoDB +
 * Bedrock), NOT an Amplify-provisioned backend. Amplify is used here only for
 * the client-side auth UI (Amazon Cognito) via Amplify UI's <Authenticator>.
 *
 * Fill these in from your Cognito User Pool. During the hackathon demo you can
 * also disable auth entirely (see EXPO_PUBLIC_REQUIRE_AUTH in src/App.tsx) and
 * talk to the API with the shared demo bearer tokens instead.
 *
 * Never put AWS credentials or secrets here — only public pool/client IDs.
 */
export function configureAmplify(): void {
  const userPoolId = process.env.EXPO_PUBLIC_COGNITO_USER_POOL_ID;
  const userPoolClientId = process.env.EXPO_PUBLIC_COGNITO_USER_POOL_CLIENT_ID;

  if (!userPoolId || !userPoolClientId) {
    // Auth is optional for local/offline demos; skip configuration so the app
    // still runs without a Cognito pool.
    return;
  }

  Amplify.configure({
    Auth: {
      Cognito: {
        userPoolId,
        userPoolClientId,
      },
    },
  });
}

export function isAuthConfigured(): boolean {
  return Boolean(
    process.env.EXPO_PUBLIC_COGNITO_USER_POOL_ID &&
      process.env.EXPO_PUBLIC_COGNITO_USER_POOL_CLIENT_ID,
  );
}
