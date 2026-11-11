/** Observable list adapter. UI nodes are created by LazyForEach, not for every retained result. */
export class ListDataSource<T> implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private items: T[] = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): T { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) { this.listeners.push(listener); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) { this.listeners.splice(index, 1); }
  }
  replace(items: T[]): void {
    this.items = items.slice();
    for (const listener of this.listeners) { listener.onDataReloaded(); }
  }
  append(items: T[]): void {
    for (const item of items) {
      const index = this.items.length;
      this.items.push(item);
      for (const listener of this.listeners) { listener.onDataAdd(index); }
    }
  }
}
