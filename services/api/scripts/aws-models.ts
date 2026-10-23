import { BedrockClient, ListFoundationModelsCommand } from '@aws-sdk/client-bedrock';

try {
  const client = new BedrockClient({ region: 'us-east-1', maxAttempts: 1 });
  const result = await client.send(new ListFoundationModelsCommand({ byOutputModality: 'TEXT', byInferenceType: 'ON_DEMAND' }), { abortSignal: AbortSignal.timeout(10_000) });
  const models = (result.modelSummaries ?? []).filter(model => model.modelLifecycle?.status === 'ACTIVE');
  console.log(JSON.stringify({ region: 'us-east-1', requestId: result.$metadata.requestId,
    models: models.map(model => ({ id: model.modelId, provider: model.providerName })) }, null, 2));
} catch (caught) {
  console.error('Bedrock model discovery failed:', caught instanceof Error ? caught.name : 'UnknownError');
  process.exitCode = 1;
}
