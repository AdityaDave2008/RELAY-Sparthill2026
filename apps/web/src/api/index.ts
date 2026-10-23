import type { RelayApi } from '../contract.ts';
import { createHttpApi } from './http.ts';
import { createMockApi } from './mock.ts';

const url = (import.meta.env.VITE_API_URL as string | undefined) || '/api';

// Shared demo tokens (services/api/README.md). Not real authentication.
export const api: RelayApi = import.meta.env.VITE_MOCK_API === 'true'
  ? createMockApi()
  : createHttpApi(url, (import.meta.env.VITE_COORDINATOR_TOKEN ?? import.meta.env.VITE_DEVICE_TOKEN) as string | undefined);
