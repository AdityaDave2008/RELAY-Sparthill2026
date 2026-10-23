import { BedrockClassifier } from './bedrock.ts';
import { DynamoRepository } from './dynamodb.ts';
import { RequestProcessor } from './processing.ts';

interface StreamEvent {
  Records: { eventName?: string; dynamodb?: { Keys?: { sk?: { S?: string } }; SequenceNumber?: string } }[];
}

export function createStreamHandler(processor: Pick<RequestProcessor, 'classify'>) {
  return async (event: StreamEvent) => {
    const batchItemFailures: { itemIdentifier: string }[] = [];
    for (const record of event.Records) {
      if (record.eventName !== 'INSERT') continue;
      const id = record.dynamodb?.Keys?.sk?.S;
      const sequence = record.dynamodb?.SequenceNumber;
      if (!id || !sequence) throw new Error('Invalid DynamoDB stream record');
      try { await processor.classify(id); }
      catch { batchItemFailures.push({ itemIdentifier: sequence }); }
    }
    return { batchItemFailures };
  };
}

let processor: RequestProcessor | undefined;
export async function handler(event: StreamEvent) {
  if (process.env.AWS_REGION !== 'us-east-1') throw new Error('This workshop requires us-east-1');
  if (!process.env.RELAY_TABLE_NAME || !process.env.BEDROCK_MODEL_ID) throw new Error('Configure the table and Bedrock model');
  processor ??= new RequestProcessor(new DynamoRepository(process.env.RELAY_TABLE_NAME),
    new BedrockClassifier({ modelId: process.env.BEDROCK_MODEL_ID, region: 'us-east-1' }));
  return createStreamHandler(processor)(event);
}
