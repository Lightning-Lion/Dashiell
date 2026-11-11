import { audio, AVVolumePanel } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { watchSizeFp } from '../../common/ScreenSize';
import { logTag } from '../../common/printLog';

@Builder
export function VolumeControlPageBuilder(name: string, param: Object) {
  VolumeControlPage()
}

@Entry
@ComponentV2
export struct VolumeControlPage {
  @Local volume: number = 0;
  pageInfos: NavPathStack | null = null
  private vSpace: number = 10
  private symbolFontSize: number = 23
  private buttonSize: number = 30

  build() {
    NavDestination() {
      Stack() {
        AVVolumePanel({
          volumeLevel: this.volume,
        })
        Column({ space: "10fp" }) {
          Button('+', { type: ButtonType.Circle })
            .fontSize(this.symbolFontSize + "fp")
            .backgroundColor($r("app.color.brand_color"))
            .width(this.buttonSize + 'fp')
            .height(this.buttonSize + 'fp')
            .aspectRatio(1)
            .onClick(async () => {
              this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                this.volume = (this.volume >= 15) ? 15 : this.volume + 1
              })
              console.debug(logTag, ':::音量+', this.volume)
              let audioManager = audio.getAudioManager();
              let audioVolumeManager = audioManager.getVolumeManager();

              audioVolumeManager.on('volumeChange', (volumeEvent: audio.VolumeEvent) => {
                console.debug(logTag, `:::Volume level: ${volumeEvent.volume} `);
              });
            })

          Slider({
            min: 0,
            max: 15,
            value: this.volume,
            style: SliderStyle.NONE,
            direction: Axis.Vertical,
            reverse: true // 竖向的Slider默认是上端是min值，下端是max值，因此想要从下往上滑动，需要设置reverse为true
          })
            .trackThickness('30vp')
            .selectedColor($r("app.color.brand_color"))
            .selectedBorderRadius(0)
            .height(`${watchSizeFp - this.vSpace - this.buttonSize - this.vSpace - this.vSpace - this.buttonSize -
            this.vSpace}fp`)
            .onChange((value: number, mode: SliderChangeMode) => {
              this.volume = value
              console.debug(logTag, 'value:' + value + 'this.sliderValue:' + this.volume + 'mode:' + mode.toString())
            })
            //list组件获焦后即可响应旋转表冠控制滑
            .focusable(true)
            .defaultFocus(true)
            .focusOnTouch(true)
            .enableHapticFeedback(true)
            .digitalCrownSensitivity(CrownSensitivity.LOW)

          Button('-', { type: ButtonType.Circle })
            .fontSize(this.symbolFontSize + "fp")
            .backgroundColor($r("app.color.brand_color"))
            .width(this.buttonSize + 'fp')
            .height(this.buttonSize + 'fp')
            .aspectRatio(1)
            .onClick(async () => {
              console.debug(logTag, 'less this.sliderValue ------ :' + this.volume)
              this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                this.volume = (this.volume <= 0) ? 0 : this.volume - 1
              })
            })
        }
        .height('100%')
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .height('100%')
      .width('100%')
      .backgroundColor(Color.Black)
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
    .onShown(() => {
      console.debug(logTag, "触发了onPageShow")
      let groupId: number = audio.DEFAULT_VOLUME_GROUP_ID;
      let audioManager = audio.getAudioManager();
      let audioVolumeManager: audio.AudioVolumeManager = audioManager.getVolumeManager();
      audioVolumeManager.getVolumeGroupManager(groupId,
        (err: BusinessError, audioVolumeGroupManager: audio.AudioVolumeGroupManager) => {
          if (err) {
            console.debug(logTag, `Failed to obtain the volume group infos list. ${err}`);
            return;
          }
          audioVolumeGroupManager.getVolume(audio.AudioVolumeType.MEDIA, (err: BusinessError, value: number) => {
            if (err) {
              console.debug(logTag, `Failed to obtain the volume. ${err}`);
              return;
            }
            this.volume = value;
            console.debug(logTag, ' debug: value = ', value);
            console.debug(logTag, 'Callback invoked to indicate that the volume is obtained.');
          });
          console.debug(logTag, 'Callback invoked to indicate that the volume group infos list is obtained.');
        });
    })
  }
}