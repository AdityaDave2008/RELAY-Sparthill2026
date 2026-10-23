import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createMessage } from '@relay/core';
import { BedrockClassifier } from '../src/bedrock.ts';
import type { ConverseCommandOutput } from '@aws-sdk/client-bedrock-runtime';

const message = createMessage({ kind: 'help_request', originDeviceId: 'resident', body: 'Four people need water on floor three.' });
const output = (value: unknown): ConverseCommandOutput => ({ $metadata: { requestId: 'unit-test-aws-request' }, stopReason: 'end_turn',
  usage: { inputTokens: 1, outputTokens: 1, totalTokens: 2 }, metrics: { latencyMs: 1 },
  output: { message: { role: 'assistant', content: [{ text: JSON.stringify(value) }] } } });
const extracted = { needs: ['water'], peopleCount: 4, locationDescription: 'Floor three', summary: 'Four people need water.' };

test('Bedrock extraction sends real Converse-shaped input and preserves provenance', async () => {
  const bedrock = new BedrockClassifier({ modelId: 'test-model', send: async (command, signal) => {
    assert.equal(command.input.modelId, 'test-model');
    assert.equal(command.input.inferenceConfig?.temperature, undefined);
    assert.ok(command.input.system?.[0].text?.includes('untrusted data'));
    const prompt = JSON.parse(command.input.messages![0].content![0].text!);
    assert.equal(prompt.unverifiedRequestText, message.body);
    assert.equal(signal.aborted, false);
    return output({ ...extracted, requiresHumanReview: false, coordinates: [1, 2] });
  } });
  const result = await bedrock.classify(message);
  assert.equal(result.requiresHumanReview, true);
  assert.equal(result.source, 'amazon-bedrock');
  assert.equal(result.awsRequestId, 'unit-test-aws-request');
  assert.equal('coordinates' in result, false);
});

test('invalid or truncated model outputs cannot become structured request facts', async () => {
  for (const value of [{ ...extracted, needs: ['invented'] }, { ...extracted, peopleCount: -4 }, { ...extracted, summary: '' }]) {
    await assert.rejects(new BedrockClassifier({ modelId: 'test-model', send: async () => output(value) }).classify(message));
  }
  await assert.rejects(new BedrockClassifier({ modelId: 'test-model', send: async () => ({ ...output(extracted), stopReason: 'max_tokens' }) }).classify(message), /complete/);
});

test('bulletin drafts use source notes and extracted needs without auto-approval', async () => {
  const draft = { message: 'Demo shelter has water.', spokenMessage: 'Demo shelter has water.', noticeTitle: 'Water', noticeLines: ['Demo shelter has water.'] };
  const bedrock = new BedrockClassifier({ modelId: 'test-model', send: async command => {
    const input = JSON.parse(command.input.messages![0].content![0].text!);
    assert.equal(input.sourceNotes, 'Verified fictional shelter note');
    assert.equal(input.language, 'English');
    assert.deepEqual(input.unverifiedRequestContext.needs, ['water']);
    return output(draft);
  } });
  const result = await bedrock.draftBulletin('Verified fictional shelter note', 'English', { ...extracted,
    needs: ['water'], requiresHumanReview: true, source: 'amazon-bedrock', modelId: 'test-model' });
  assert.equal(result.requiresHumanApproval, true);
  assert.equal(result.message, draft.message);
  assert.equal(result.source, 'amazon-bedrock');
});
