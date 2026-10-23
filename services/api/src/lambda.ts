import { MAX_REQUEST_BYTES } from './app.ts';
import { configuredApi } from './config.ts';

export interface HttpEvent {
  rawPath: string;
  rawQueryString?: string;
  headers?: Record<string, string | undefined>;
  requestContext: { http: { method: string } };
  body?: string;
  isBase64Encoded?: boolean;
}

export function createLambdaHandler(api: (request: Request) => Promise<Response>) {
  return async (event: HttpEvent) => {
    const body = event.body ? Buffer.from(event.body, event.isBase64Encoded ? 'base64' : 'utf8') : undefined;
    if (body && body.length > MAX_REQUEST_BYTES) return { statusCode: 413, headers: { 'content-type': 'application/json' }, body: JSON.stringify({ error: { code: 'body_too_large', message: 'Request body exceeds 2 MiB' } }) };
    const headers = new Headers();
    for (const [key, value] of Object.entries(event.headers ?? {})) if (value !== undefined) headers.set(key, value);
    const method = event.requestContext.http.method;
    const url = `https://relay.invalid${event.rawPath}${event.rawQueryString ? '?' + event.rawQueryString : ''}`;
    const response = await api(new Request(url, { method, headers,
      ...(!['GET', 'HEAD'].includes(method) && body ? { body: body.toString('utf8') } : {}),
    }));
    return { statusCode: response.status, headers: Object.fromEntries(response.headers), body: await response.text() };
  };
}

let configuredHandler: ReturnType<typeof createLambdaHandler> | undefined;
export async function handler(event: HttpEvent) {
  configuredHandler ??= createLambdaHandler(configuredApi(process.env, true));
  return configuredHandler(event);
}
