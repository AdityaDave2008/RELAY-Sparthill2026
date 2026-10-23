import type { Classifier } from './bedrock.ts';
import type { Repository, RequestRecord } from './repository.ts';

// Durable requests are the job source. A restart recovers unclassified records;
// upload receipts never wait for inference. Explicit UI actions share in-flight
// work with this processor rather than issuing a second local model invocation.
export class RequestProcessor {
  private repository: Repository;
  private classifier: Classifier;
  private now: () => number;
  private inFlight = new Map<string, Promise<RequestRecord | undefined>>();
  private queued = new Set<string>();
  private failures = new Map<string, { count: number; nextAt: number }>();
  private running?: Promise<void>;
  private timer?: ReturnType<typeof setTimeout>;
  private recovery?: ReturnType<typeof setInterval>;
  private stopped = false;

  constructor(repository: Repository, classifier: Classifier, now: () => number = Date.now) {
    this.repository = repository; this.classifier = classifier; this.now = now;
  }

  classify(id: string): Promise<RequestRecord | undefined> {
    const existing = this.inFlight.get(id);
    if (existing) return existing;
    const work = (async () => {
      const record = await this.repository.get(id);
      if (!record || record.message.kind !== 'help_request' || record.message.expiresAt <= this.now()) return undefined;
      if (record.classification) return record;
      const result = await this.classifier.classify(record.message);
      const updated = await this.repository.classify(id, result, this.now());
      this.failures.delete(id);
      return updated;
    })().finally(() => this.inFlight.delete(id));
    this.inFlight.set(id, work);
    return work;
  }

  schedule(id: string): void {
    const failure = this.failures.get(id);
    if (this.stopped || this.queued.size >= 1000 || (failure && (failure.count >= 3 || failure.nextAt > this.now()))) return;
    this.queued.add(id);
    if (!this.timer) {
      this.timer = setTimeout(() => { this.timer = undefined; void this.drain(); }, 0);
      this.timer.unref();
    }
  }

  drain(): Promise<void> {
    if (this.running) return this.running;
    this.running = (async () => {
      while (!this.stopped && this.queued.size) {
        const id = this.queued.values().next().value!;
        this.queued.delete(id);
        try { await this.classify(id); }
        catch {
          const count = (this.failures.get(id)?.count ?? 0) + 1;
          this.failures.set(id, { count, nextAt: this.now() + 30_000 * 2 ** (count - 1) });
        }
      }
    })().finally(() => { this.running = undefined; });
    return this.running;
  }

  async recover(): Promise<void> {
    let afterId: string | undefined;
    for (let page = 0; page < 200 && !this.stopped; page++) {
      const records = await this.repository.page({ kind: 'help_request', now: this.now(), limit: 50, afterId });
      for (const record of records.records) if (!record.classification) this.schedule(record.message.id);
      if (!records.afterId) return;
      afterId = records.afterId;
    }
  }

  start(): void {
    const recover = () => { void this.recover().catch(() => { /* next recovery pass retries storage failures */ }); };
    recover();
    this.recovery = setInterval(recover, 30_000);
    this.recovery.unref();
  }

  stop(): void {
    this.stopped = true;
    clearTimeout(this.timer); clearInterval(this.recovery);
  }
}
