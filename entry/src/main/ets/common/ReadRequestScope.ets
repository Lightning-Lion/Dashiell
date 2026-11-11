import { http } from '@kit.NetworkKit';

export class ReadRequestCancelled extends Error {
  constructor() { super('页面请求已取消'); }
}

class PendingRead {
  client: http.HttpRequest;
  cancel: () => void;
  constructor(client: http.HttpRequest, cancel: () => void) { this.client = client; this.cancel = cancel; }
}
class PendingDelay {
  timer: number;
  resolve: () => void;
  constructor(timer: number, resolve: () => void) { this.timer = timer; this.resolve = resolve; }
}

/** Page-owned HTTP and retry delays. Cancel settles waiters even if the native callback never arrives. */
export class ReadRequestScope {
  private generation: number = 0;
  private requests: Set<PendingRead> = new Set();
  private delays: Set<PendingDelay> = new Set();

  cancel(): void {
    console.info('READ_SCOPE cancel pending=' + this.requests.size + ' retryDelays=' + this.delays.size);
    this.generation++;
    for (const pending of Array.from(this.requests)) { pending.cancel(); }
    for (const delay of this.delays) { clearTimeout(delay.timer); delay.resolve(); }
    this.delays.clear();
  }

  private ensureCurrent(generation: number): void {
    if (generation !== this.generation) { throw new ReadRequestCancelled(); }
  }

  async get(address: string, options: http.HttpRequestOptions): Promise<http.HttpResponse> {
    return this.request(address, options, 1);
  }

  async request(address: string, options: http.HttpRequestOptions, retries: number = 0): Promise<http.HttpResponse> {
    const generation = this.generation;
    const retryCount = Math.min(1, Math.max(0, retries));
    for (let attempt = 0; attempt <= retryCount; attempt++) {
      this.ensureCurrent(generation);
      try {
        const response = await this.once(address, options);
        this.ensureCurrent(generation);
        return response;
      } catch (error) {
        this.ensureCurrent(generation);
        if (error instanceof ReadRequestCancelled || attempt === retryCount) { throw error as Error; }
        // Only transport exceptions retry. HTTP status and parsing remain caller decisions.
        await this.delay();
      }
    }
    throw new Error('网络请求未完成');
  }

  private delay(): Promise<void> {
    return new Promise<void>((resolve) => {
      const pending = new PendingDelay(setTimeout(() => {
        this.delays.delete(pending);
        resolve();
      }, 250), resolve);
      this.delays.add(pending);
    });
  }

  private once(address: string, options: http.HttpRequestOptions): Promise<http.HttpResponse> {
    return new Promise<http.HttpResponse>((resolve, reject) => {
      const client = http.createHttp();
      let settled = false;
      const pending = new PendingRead(client, () => {
        if (settled) { return; }
        settled = true;
        this.requests.delete(pending);
        try { client.destroy(); } catch (error) { /* Settling the request must not depend on native cleanup. */ }
        reject(new ReadRequestCancelled());
      });
      const finish = (): void => {
        this.requests.delete(pending);
        try { client.destroy(); } catch (error) { /* Settling the request must not depend on native cleanup. */ }
      };
      this.requests.add(pending);
      try {
        client.request(address, options).then((response: http.HttpResponse) => {
          if (settled) { return; }
          settled = true;
          finish();
          resolve(response);
        }).catch((error: Error) => {
          if (settled) { return; }
          settled = true;
          finish();
          reject(error);
        });
      } catch (error) {
        if (settled) { return; }
        settled = true;
        finish();
        reject(error);
      }
    });
  }
}
