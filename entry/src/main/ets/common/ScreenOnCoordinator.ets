/** Serial, last-desired-state arbitration for asynchronous native window writes. */
export class ScreenOnCoordinator {
  private owners: Set<string> = new Set();
  private foreground: boolean = true;
  private applied: boolean | undefined = undefined;
  private dirty: boolean = false;
  private windowGeneration: number = 0;
  private running: Promise<void> | undefined = undefined;
  private apply: (enabled: boolean) => Promise<void>;

  constructor(apply: (enabled: boolean) => Promise<void>) { this.apply = apply; }

  request(owner: string, enabled: boolean): Promise<void> {
    if (enabled) { this.owners.add(owner); } else { this.owners.delete(owner); }
    return this.sync();
  }
  setForeground(value: boolean): Promise<void> {
    this.foreground = value;
    return this.sync();
  }
  resetWindow(clearOwners: boolean = false): Promise<void> {
    this.windowGeneration++;
    if (clearOwners) { this.owners.clear(); }
    this.applied = undefined;
    return this.sync();
  }
  hasRequests(): boolean { return this.owners.size > 0; }
  hasRequest(prefix: string): boolean {
    for (const owner of this.owners) { if (owner === prefix || owner.startsWith(prefix + ':')) { return true; } }
    return false;
  }

  private async sync(): Promise<void> {
    this.dirty = true;
    if (this.running !== undefined) {
      await this.running;
      // A caller can arrive between drain completion and clearing the in-flight promise.
      if (this.dirty) { await this.sync(); }
      return;
    }
    const task = this.drain();
    this.running = task;
    try { await task; }
    finally { if (this.running === task) { this.running = undefined; } }
    if (this.dirty) { await this.sync(); }
  }

  private async drain(): Promise<void> {
    while (this.dirty) {
      this.dirty = false;
      const desired = this.foreground && this.hasRequests();
      if (this.applied === desired) { continue; }
      const generation = this.windowGeneration;
      try {
        await this.apply(desired);
        this.applied = generation === this.windowGeneration ? desired : undefined;
      } catch (error) {
        this.applied = undefined;
        // Do not lose a newer OFF/new-window request behind a failed obsolete write.
        // Identical failed requests are not retried in a busy loop.
        const newest = this.foreground && this.hasRequests();
        if (this.dirty && (newest !== desired || generation !== this.windowGeneration)) { continue; }
        throw error as Error;
      }
    }
  }
}
