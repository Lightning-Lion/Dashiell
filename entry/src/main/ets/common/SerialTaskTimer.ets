/** Serial polling with a generation guard; old completions cannot become current after restart. */
export class SerialTaskTimer {
  private timer: number | undefined = undefined;
  private generation: number = 0;
  private runningGeneration: number = -1;
  start(task: (current: () => boolean) => Promise<void>, interval: number): void {
    this.stop();
    const generation = this.generation;
    const current = (): boolean => generation === this.generation && this.timer !== undefined;
    const run = async (): Promise<void> => {
      if (!current() || this.runningGeneration === generation) { return; }
      this.runningGeneration = generation;
      try { await task(current); }
      catch (error) { /* Navigation and teardown can invalidate a native bridge call. */ }
      finally { if (this.runningGeneration === generation) { this.runningGeneration = -1; } }
    };
    this.timer = setInterval(() => run(), interval);
    run();
  }
  stop(): void {
    this.generation++;
    if (this.timer !== undefined) { clearInterval(this.timer); }
    this.timer = undefined;
  }
}
