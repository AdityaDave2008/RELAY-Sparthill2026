// Client for services/api. Contract: services/api/README.md.
import { LANG_NAME, type BulletinDraft, type Health, type Lang, type Pictogram, type RelayApi, type RequestRecord, type WarningDraft, type WireMessage } from '../contract.ts';

export class ApiError extends Error {
  readonly code: string;
  readonly status: number;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function createHttpApi(baseUrl: string, token?: string): RelayApi {
  const base = baseUrl.replace(/\/$/, '');

  async function call<T>(method: string, path: string, body?: unknown): Promise<T> {
    const headers: Record<string, string> = {};
    if (body !== undefined) headers['content-type'] = 'application/json';
    if (token) headers.authorization = `Bearer ${token}`;
    const res = await fetch(base + path, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(30_000),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new ApiError(res.status, data?.error?.code ?? `http_${res.status}`, data?.error?.message ?? res.statusText);
    return data as T;
  }

  const q = (params: Record<string, string | null>) =>
    new URLSearchParams(Object.entries(params).filter((e): e is [string, string] => e[1] !== null)).toString();

  return {
    mode: 'live',
    health: () => call<Health>('GET', '/v1/health'),
    uploadBatch: (deviceId, messages) => call('POST', '/v1/messages/batch', { deviceId, messages }),
    fetchMessages: (deviceId, cursor) => call('GET', `/v1/messages?${q({ deviceId, cursor, limit: '50' })}`),
    requests: (cursor) => call('GET', `/v1/requests?${q({ cursor, limit: '50' })}`),
    classify: (id) => call<RequestRecord>('POST', `/v1/requests/${encodeURIComponent(id)}/classify`),
    reply: async (id, replyId, body) =>
      (await call<{ message: WireMessage }>('POST', `/v1/requests/${encodeURIComponent(id)}/replies`, { id: replyId, body })).message,
    publishWarning: async (input) => (await call<{ message: WireMessage }>('POST', '/v1/warnings', input)).message,
    // One Bedrock call per language, in parallel. English is the approved
    // text; the others become translations.
    draftWarning: async (rawReport: string, _incidentId: string, languages: Lang[]): Promise<WarningDraft> => {
      const langs: Lang[] = ['en', ...languages.filter((l) => l !== 'en')];
      const drafts = await Promise.all(
        langs.map((l) => call<BulletinDraft>('POST', '/v1/bulletins/draft', { notes: rawReport, language: LANG_NAME[l] })),
      );
      const [en] = drafts;
      return {
        title: en.noticeTitle,
        body: en.message,
        noticeLines: en.noticeLines,
        translations: Object.fromEntries(langs.slice(1).map((l, i) => [l, { title: drafts[i + 1].noticeTitle, body: drafts[i + 1].message }])),
        pictograms: pictogramsFor(`${en.noticeTitle} ${en.message} ${en.noticeLines.join(' ')}`),
        radioScript: en.spokenMessage,
        uncertain: [],
        source: en.source,
        modelId: en.modelId,
      };
    },
  };
}

// Pictograms are picked locally from the English draft, not by Bedrock.
const PICTO_WORDS: [Pictogram, RegExp][] = [
  ['water', /water/i],
  ['food', /food|meal/i],
  ['medical', /medic|clinic|insulin|first aid/i],
  ['shelter', /shelter|cots|gym/i],
  ['danger', /avoid|danger|closed|flood|fire/i],
  ['route', /route|road|bridge/i],
];

function pictogramsFor(text: string): Pictogram[] {
  const found = PICTO_WORDS.filter(([, re]) => re.test(text)).map(([p]) => p);
  return found.length ? found : ['info'];
}
