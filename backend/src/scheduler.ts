export type CollectionSchedulerOptions = {
  intervalMilliseconds: number;
  runCollection: () => Promise<void>;
  onError?: (error: unknown) => void;
};

export class CollectionScheduler {
  private timer: NodeJS.Timeout | undefined;
  private running: Promise<void> | undefined;
  private stopped = true;

  constructor(private readonly options: CollectionSchedulerOptions) {
    if (!Number.isFinite(options.intervalMilliseconds) || options.intervalMilliseconds <= 0) {
      throw new Error("Collection interval must be a positive number");
    }
  }

  start(): void {
    if (!this.stopped) return;
    this.stopped = false;
    void this.tick();
  }

  async stop(): Promise<void> {
    this.stopped = true;
    if (this.timer) clearTimeout(this.timer);
    await this.running;
  }

  private async tick(): Promise<void> {
    if (this.stopped) return;
    this.running = this.options.runCollection().catch((error) => this.options.onError?.(error));
    await this.running;
    this.running = undefined;
    if (!this.stopped) {
      this.timer = setTimeout(() => void this.tick(), this.options.intervalMilliseconds);
    }
  }
}
