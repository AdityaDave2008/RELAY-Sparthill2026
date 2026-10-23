import { BedrockClassifier } from './bedrock.ts';
import { createApi } from './app.ts';
import { DynamoRepository } from './dynamodb.ts';
import { FileRepository } from './repository.ts';
import { RequestProcessor } from './processing.ts';

export function configuredApi(env: NodeJS.ProcessEnv = process.env, lambda = false): ReturnType<typeof createApi> & { close(): void } {
  if ((env.AWS_REGION && env.AWS_REGION !== 'us-east-1') || (env.AWS_DEFAULT_REGION && env.AWS_DEFAULT_REGION !== 'us-east-1')) {
    throw new Error('This workshop requires AWS Region us-east-1');
  }
  const host = env.RELAY_HOST ?? '127.0.0.1';
  const local = !lambda && ['127.0.0.1', 'localhost', '::1'].includes(host);
  const deviceToken = env.RELAY_DEVICE_TOKEN || undefined;
  const coordinatorToken = env.RELAY_COORDINATOR_TOKEN || undefined;
  if ((!local || deviceToken || coordinatorToken) &&
      (!deviceToken || !coordinatorToken || deviceToken.length < 16 || coordinatorToken.length < 16 || deviceToken === coordinatorToken)) {
    throw new Error('Configure different RELAY_DEVICE_TOKEN and RELAY_COORDINATOR_TOKEN values, each at least 16 characters');
  }
  if (lambda && !env.RELAY_TABLE_NAME) throw new Error('RELAY_TABLE_NAME is required in Lambda');
  const origins = (env.RELAY_ALLOWED_ORIGINS ?? 'http://localhost:5173,http://127.0.0.1:5173').split(',').map(s => s.trim()).filter(Boolean);
  for (const origin of origins) {
    const parsed = new URL(origin);
    if (!['http:', 'https:'].includes(parsed.protocol) || parsed.origin !== origin) throw new Error('Allowed origins must be exact HTTP(S) origins');
  }
  const repository = env.RELAY_TABLE_NAME ? new DynamoRepository(env.RELAY_TABLE_NAME) : new FileRepository(env.RELAY_DATA_FILE ?? './data/relay.json');
  const classifier = env.BEDROCK_MODEL_ID ? new BedrockClassifier({ modelId: env.BEDROCK_MODEL_ID, region: 'us-east-1' }) : undefined;
  const processor = classifier ? new RequestProcessor(repository, classifier) : undefined;
  if (!lambda) processor?.start();
  const api = createApi({
    repository, classifier, processor, autoClassify: !lambda,
    deviceToken, coordinatorToken, allowUnauthenticated: local,
    allowedOrigins: origins,
  });
  return Object.assign(api, { close: () => processor?.stop() });
}
