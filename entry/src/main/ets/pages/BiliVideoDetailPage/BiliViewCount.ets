@ComponentV2
export struct BiliViewCount {
  // 这个视频得到的总播放量
  @Param @Require view: number

  build() {
    Column() {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Column() {
          Image($r("app.media.bili_video_detail_page_watch_count"))
            .objectFit(ImageFit.Cover)
            .width("18fp")
            .height("18fp")
          Text(this.formatNumber(this.view))
            .fontSize(12)
            .fontColor('#AAAAAA')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Center)
      }
      .onClick(() => {
        this.getUIContext().getPromptAction().showToast({ message:"播放量："+this.formatNumber(this.view) })
      })
      .backgroundColor(Color.Transparent)
    }
    .layoutWeight(1)
  }

  // 格式化数字
  formatNumber(num: number): string {
    //（只用"万"或"亿"单位，不显示.0）
    if (num >= 100000000) {
      const value = num / 100000000;
      const formatted = value.toFixed(1);
      return formatted.endsWith('.0') ? formatted.slice(0, -2) + '亿' : formatted + '亿';
    } else if (num >= 10000) {
      const value = num / 10000;
      const formatted = value.toFixed(1);
      return formatted.endsWith('.0') ? formatted.slice(0, -2) + '万' : formatted + '万';
    }
    return num.toString();
  }
}