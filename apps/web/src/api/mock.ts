// In-browser stand-in for services/api, used only when VITE_API_URL is unset.
// It mirrors the HTTP contract and keeps state in localStorage, so a resident
// tab and a coordinator tab in one browser see each other. Its "AI" is
// keyword matching, labelled MOCK wherever it appears. It is not Bedrock.
import { createMessage, validateMessage } from '@relay/core';
import {
  LANG_NAME,
  parseRequestBody,
  type Classification,
  type Need,
  type Pictogram,
  type RelayApi,
  type RequestRecord,
  type WarningDraft,
  type WireMessage,
} from '../contract.ts';
import { zoneName } from '../zones.ts';

export const MOCK_MODEL = 'mock-keyword-matcher';
const KEY = 'relay.mock.server.v2';

interface ServerState {
  requests: RequestRecord[];
  outbound: WireMessage[]; // warnings and replies
}

function load(): ServerState {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) return JSON.parse(raw) as ServerState;
  } catch {
    // fall through
  }
  return { requests: [], outbound: [] };
}

function save(state: ServerState): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(state));
  } catch {
    // storage blocked: the mock forgets
  }
}

const delay = (ms: number) => new Promise((r) => setTimeout(r, ms));

const NEED_WORDS: [Need, RegExp][] = [
  ['water', /\b(water|thirst|drink)/i],
  ['food', /\b(food|hungry|meal|formula|eat)/i],
  ['medical', /\b(medic|insulin|diabet|injur|hurt|bleed|oxygen|dialysis|pregnan|doctor|prescription)/i],
  ['shelter', /\b(shelter|roof|cold|tent|blanket)/i],
  ['evacuation', /\b(evacuat|trapped|stuck|flood|fire|smoke)/i],
  ['power', /\b(power|electric|generator|charg|battery)/i],
];

function mockClassify(message: WireMessage): Classification {
  const parsed = parseRequestBody(message.body);
  const needs = new Set<string>(parsed.needs);
  for (const [need, re] of NEED_WORDS) if (re.test(parsed.notes)) needs.add(need);
  const inText = /(\d+)\s*(people|persons|adults|of us|residents)/i.exec(parsed.notes);
  const where = /\b(at|near|on|behind)\s+([^.,;\n]{3,60})/i.exec(parsed.notes);
  return {
    needs: [...needs],
    peopleCount: parsed.people ?? (inText ? Number(inText[1]) : null),
    locationDescription: where ? where[2].trim() : null,
    summary: parsed.notes.split(/[.!?\n]/)[0]?.trim() || `Needs ${[...needs].join(', ') || 'help'}`,
    requiresHumanReview: true,
    source: 'mock',
    modelId: MOCK_MODEL,
  };
}

const PICTO_WORDS: [Pictogram, RegExp][] = [
  ['water', /water/i],
  ['food', /food|meal/i],
  ['medical', /medic|clinic|first aid|insulin/i],
  ['shelter', /shelter|gym|school|church/i],
  ['danger', /avoid|danger|closed|flood|fire|do not/i],
  ['route', /route|road|bridge|street|via/i],
];

export function createMockApi(): RelayApi {
  return {
    mode: 'mock',

    async health() {
      return { ok: true, mode: 'simulation', storage: 'browser-mock', bedrockConfigured: false };
    },

    async uploadBatch(_deviceId, messages) {
      await delay(400);
      const state = load();
      const acceptedIds: string[] = [];
      const rejected: { id: string; reason: string }[] = [];
      for (const m of messages) {
        const errors = validateMessage(m);
        if (errors.length) rejected.push({ id: String(m?.id), reason: errors.join(', ') });
        else {
          if (m.kind === 'help_request' && !state.requests.some((r) => r.message.id === m.id)) {
            state.requests.unshift({ message: m, receivedAt: Date.now() });
          }
          acceptedIds.push(m.id);
        }
      }
      save(state);
      return { acceptedIds, rejected };
    },

    async fetchMessages(deviceId) {
      await delay(200);
      const messages = load().outbound.filter((m) => m.kind === 'warning' || m.recipientDeviceId === deviceId);
      return { messages, nextCursor: null };
    },

    async requests() {
      return { requests: load().requests, nextCursor: null };
    },

    async classify(id) {
      await delay(1100);
      const state = load();
      const record = state.requests.find((r) => r.message.id === id);
      if (!record) throw new Error('Request not found');
      record.classification = mockClassify(record.message);
      save(state);
      return record;
    },

    async reply(id, replyId, body) {
      await delay(300);
      const state = load();
      const record = state.requests.find((r) => r.message.id === id);
      if (!record) throw new Error('Request not found');
      record.repliedAt ??= Date.now();
      const existing = state.outbound.find((m) => m.id === replyId);
      if (existing) return existing;
      const message: WireMessage = {
        ...createMessage({ id: replyId, kind: 'ack', replyTo: id, originDeviceId: 'coordinator', body }),
        recipientDeviceId: record.message.originDeviceId,
      };
      state.outbound.push(message);
      save(state);
      return message;
    },

    async publishWarning(input) {
      await delay(500);
      const state = load();
      const message: WireMessage = {
        ...createMessage({ id: input.id, kind: 'warning', originDeviceId: 'coordinator', body: input.body, ttlMs: input.ttlMs }),
        ...(input.incidentId && { incidentId: input.incidentId }),
        ...(input.title && { title: input.title }),
        ...(input.translations && { translations: input.translations }),
      };
      state.outbound.push(message);
      save(state);
      return message;
    },

    async draftWarning(rawReport, incidentId, languages): Promise<WarningDraft> {
      await delay(1200);
      const sentences = rawReport.split(/(?<=[.!?])\s+/).map((s) => s.trim()).filter(Boolean);
      const title = (sentences[0] ?? 'Emergency update').replace(/[.!?]$/, '').slice(0, 80);
      const body = sentences.slice(0, 4).join(' ');
      const pictograms = PICTO_WORDS.filter(([, re]) => re.test(rawReport)).map(([p]) => p);
      return {
        title,
        body,
        noticeLines: sentences.slice(0, 4),
        translations: Object.fromEntries(
          languages.filter((l) => l !== 'en').map((l) => [l, { title: `[${l}] ${title}`, body: `[${l}: translation needs Bedrock] ${body}` }]),
        ),
        pictograms: pictograms.length ? pictograms : ['info'],
        radioScript: `This is an emergency update for ${zoneName(incidentId)}. ${body} Again: ${title}.`,
        uncertain: /\b(may|might|unconfirmed|reported|possibly)\b/i.test(rawReport) ? ['Report contains unconfirmed details'] : [],
        source: 'mock',
        modelId: MOCK_MODEL,
      };
    },

    async briefing(zones) {
      await delay(1500);
      const open = load().requests.filter((r) => !load().outbound.some((m) => m.replyTo === r.message.id));
      const scored = open
        .map((r) => {
          const c = r.classification ?? mockClassify(r.message);
          const score = (c.needs.includes('medical') ? 3 : 0) + (c.needs.includes('evacuation') ? 3 : 0) + (c.needs.includes('water') ? 1 : 0) + Math.min(3, (c.peopleCount ?? 1) / 10);
          return { r, c, score };
        })
        .sort((a, b) => b.score - a.score);
      const zoneSummaries = zones.map((z) => {
        const inZone = scored.filter((s) => s.r.message.incidentId === z.id);
        const needs = [...new Set(inZone.flatMap((s) => s.c.needs))];
        return {
          incidentId: z.id,
          summary: inZone.length ? `${inZone.length} open request(s), ${inZone.reduce((n, s) => n + (s.c.peopleCount ?? 1), 0)} people` : 'No open requests',
          unmetNeeds: needs,
          suggestedAction: z.reach.none > 0.1 ? 'Send a volunteer with printed notices and help cards' : needs.length ? `Route ${needs.join(', ')} supplies` : 'Keep monitoring',
        };
      });
      return {
        generatedAt: Date.now(),
        headline: scored.length ? `${scored.length} open requests. Start with ${zoneName(scored[0].r.message.incidentId)}.` : 'No open requests.',
        priorities: scored.slice(0, 5).map((s, i) => ({ requestId: s.r.message.id, rank: i + 1, reason: s.c.summary })),
        zones: zoneSummaries,
        gaps: zones.filter((z) => z.connectivity === 'offline' && !scored.some((s) => s.r.message.incidentId === z.id)).map((z) => `No requests from ${z.name}. It has no signal, so silence does not mean it is safe.`),
        requiresHumanReview: true,
        source: 'mock',
        modelId: MOCK_MODEL,
      };
    },

    async responseDraft(id, notes, language) {
      await delay(1400);
      const state = load();
      const record = state.requests.find((r) => r.message.id === id);
      if (!record) throw new Error('Request not found');
      record.classification ??= mockClassify(record.message);
      save(state);
      const facts = notes.trim() || 'Your request has been received.';
      return {
        request: record,
        draft: {
          message: `${language !== 'en' ? `[${language}: translation needs Bedrock] ` : ''}We received your request. ${facts} Stay where you are if it is safe.`,
          spokenMessage: `Message for the household that asked for ${record.classification.needs.join(' and ') || 'help'}. ${facts}`,
          noticeTitle: 'Reply to your request',
          noticeLines: [facts],
          language: LANG_NAME[language],
          requiresHumanApproval: true,
          source: 'mock',
          modelId: MOCK_MODEL,
        },
      };
    },

    async readCard() {
      await delay(1500);
      return {
        needs: ['water'],
        peopleCount: null,
        locationDescription: null,
        notes: 'Mock reading: connect the API to have Amazon Bedrock read the photo.',
        unreadable: ['Mock mode cannot read images'],
        requiresHumanReview: true,
        source: 'mock',
        modelId: MOCK_MODEL,
      };
    },
  };
}
