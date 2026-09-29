import type { WorkerRequest, WorkerResponse } from '../routing/protocol';

type Listener = (msg: WorkerResponse) => void;

/** Thin wrapper over the routing worker: request ids + a single listener. */
export class RoutingWorker {
  private readonly worker: Worker;
  private nextId = 1;
  private listener: Listener = () => {};

  constructor() {
    this.worker = new Worker(new URL('../routing/worker.ts', import.meta.url), { type: 'module' });
    this.worker.onmessage = (ev: MessageEvent<WorkerResponse>) => this.listener(ev.data);
    this.worker.onerror = (ev) => this.listener({ type: 'error', requestId: -1, message: ev.message || 'Worker crashed' });
  }

  onMessage(l: Listener): void {
    this.listener = l;
  }

  /** Sends a request (minus its id) and returns the id assigned to it. */
  send(req: DistributiveOmit<WorkerRequest, 'requestId'>): number {
    const requestId = this.nextId++;
    this.worker.postMessage({ ...req, requestId } as WorkerRequest);
    return requestId;
  }
}

type DistributiveOmit<T, K extends keyof T> = T extends unknown ? Omit<T, K> : never;
