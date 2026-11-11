import { ApiResponseRelatedData } from "./BiliVideoDetailPage";


class BasicDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private originDataArray: ApiResponseRelatedData[] = [];

  public totalCount(): number {
    return 0;
  }

  public getData(index: number): ApiResponseRelatedData {
    return this.originDataArray[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      console.debug('add listener');
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      console.debug('remove listener');
      this.listeners.splice(pos, 1);
    }
  }

  notifyDataReload(): void {
    this.listeners.forEach(listener => {
      listener.onDataReloaded();
    })
  }

  notifyDataAdd(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataAdd(index);
    })
  }

  notifyDataChange(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataChange(index);
    })
  }

  notifyDataDelete(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataDelete(index);
    })
  }

  notifyDataMove(from: number, to: number): void {
    this.listeners.forEach(listener => {
      listener.onDataMove(from, to);
    })
  }

  notifyDatasetChange(operations: DataOperation[]): void {
    this.listeners.forEach(listener => {
      listener.onDatasetChange(operations);
    })
  }
}


export class RelatedVideosViewDataSource extends BasicDataSource {
  private dataArray: ApiResponseRelatedData[] = [];

  public totalCount(): number {
    return this.dataArray.length;
  }

  public getData(index: number): ApiResponseRelatedData {
    return this.dataArray[index];
  }

  public pushData(data: ApiResponseRelatedData): void {
    this.dataArray.push(data);
    this.notifyDataAdd(this.dataArray.length - 1);
  }

  public updateAllData(allData: ApiResponseRelatedData[]): void {
    this.dataArray = allData;
    this.notifyDataReload();
  }
}
