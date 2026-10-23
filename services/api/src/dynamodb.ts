import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, PutCommand, QueryCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import type { Classification, PageOptions, RecordPage, Repository, RequestRecord } from './repository.ts';

// A single messages partition suits the hackathon dataset and keeps reads
// strongly consistent. Split by incident/recipient before production scaling.
export class DynamoRepository implements Repository {
  readonly kind = 'dynamodb' as const;
  private client: DynamoDBDocumentClient;
  private table: string;

  constructor(table: string, client = DynamoDBDocumentClient.from(new DynamoDBClient({ region: 'us-east-1' }), {
    marshallOptions: { removeUndefinedValues: true },
  })) { this.table = table; this.client = client; }

  async get(id: string): Promise<RequestRecord | undefined> {
    const result = await this.client.send(new GetCommand({ TableName: this.table, Key: this.key(id), ConsistentRead: true }));
    return result.Item?.payload as RequestRecord | undefined;
  }

  async putIfAbsent(record: RequestRecord): Promise<boolean> {
    try {
      await this.client.send(new PutCommand({ TableName: this.table,
        Item: { ...this.key(record.message.id), payload: record, ttl: Math.floor(record.message.expiresAt / 1000) },
        ConditionExpression: 'attribute_not_exists(pk) AND attribute_not_exists(sk)',
      }));
      return true;
    } catch (error) {
      if (error instanceof Error && error.name === 'ConditionalCheckFailedException') return false;
      throw error;
    }
  }

  async classify(id: string, classification: Classification, now: number): Promise<RequestRecord | undefined> {
    try {
      const result = await this.client.send(new UpdateCommand({
        TableName: this.table, Key: this.key(id),
        UpdateExpression: 'SET #payload.#classification = :classification',
        ConditionExpression: 'attribute_exists(pk) AND #payload.#message.#expires > :now',
        ExpressionAttributeNames: { '#payload': 'payload', '#classification': 'classification', '#message': 'message', '#expires': 'expiresAt' },
        ExpressionAttributeValues: { ':classification': classification, ':now': now },
        ReturnValues: 'ALL_NEW',
      }));
      return result.Attributes?.payload as RequestRecord | undefined;
    } catch (error) {
      if (error instanceof Error && error.name === 'ConditionalCheckFailedException') return undefined;
      throw error;
    }
  }

  async page(options: PageOptions): Promise<RecordPage> {
    const names: Record<string, string> = { '#pk': 'pk', '#payload': 'payload', '#message': 'message', '#kind': 'kind', '#expires': 'expiresAt' };
    const values: Record<string, unknown> = { ':partition': 'messages', ':now': options.now };
    let filter: string;
    if (options.kind) {
      values[':kind'] = options.kind;
      filter = '#payload.#message.#kind = :kind';
    } else {
      names['#recipient'] = 'recipientDeviceId';
      Object.assign(values, { ':warning': 'warning', ':ack': 'ack', ':recipient': options.recipientDeviceId });
      filter = '(#payload.#message.#kind = :warning OR (#payload.#message.#kind = :ack AND #payload.#message.#recipient = :recipient))';
    }
    const result = await this.client.send(new QueryCommand({ TableName: this.table,
      KeyConditionExpression: '#pk = :partition',
      FilterExpression: `#payload.#message.#expires > :now AND ${filter}`,
      ExpressionAttributeNames: names, ExpressionAttributeValues: values,
      Limit: options.limit, ConsistentRead: true,
      ...(options.afterId ? { ExclusiveStartKey: this.key(options.afterId) } : {}),
    }));
    return { records: (result.Items ?? []).map(item => item.payload as RequestRecord),
      afterId: result.LastEvaluatedKey?.sk as string ?? null };
  }

  async markReplied(id: string, repliedAt: number): Promise<void> {
    await this.client.send(new UpdateCommand({ TableName: this.table, Key: this.key(id),
      UpdateExpression: 'SET #payload.#replied = if_not_exists(#payload.#replied, :at)',
      ConditionExpression: 'attribute_exists(pk)',
      ExpressionAttributeNames: { '#payload': 'payload', '#replied': 'repliedAt' },
      ExpressionAttributeValues: { ':at': repliedAt },
    }));
  }

  private key(id: string): { pk: string; sk: string } { return { pk: 'messages', sk: id }; }
}
