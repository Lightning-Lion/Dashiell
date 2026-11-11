import { logTag } from '../../common/printLog'
import { AppDatabase } from '../../common/storage/AppDatabase'
import { StorageKeys, StorageNamespaces } from '../../common/storage/StorageKeys'
import { DarkTheme } from '../../common/Theme'
import { AboutSubpageHeader } from '../AboutPage/AboutSubpageHeader'

export class PersonalizedSettingsPersist {
  private context: Context

  private constructor(context: Context) {
    this.context = context
  }

  // Factory方法
  static async asyncInit(context: Context): Promise<PersonalizedSettingsPersist> {
    return new PersonalizedSettingsPersist(context)
  }

  async isEnablePersonalized(): Promise<boolean> {
    try {
      const db = await AppDatabase.open(this.context)
      return await db.values.getBoolean(StorageKeys.PERSONALIZED_RECOMMENDATION_ENABLED, true)
    } catch (error) {
      console.debug(logTag, '读取个性化推荐设置失败: ' + PersonalizedSettingsPersist.describe(error))
      return true
    }
  }

  async enablePersonalized(): Promise<void> {
    await this.setEnabled(true)
  }

  async disablePersonalized(): Promise<void> {
    await this.setEnabled(false)
  }

  private async setEnabled(enabled: boolean): Promise<void> {
    try {
      const db = await AppDatabase.open(this.context)
      await db.values.setBoolean(StorageKeys.PERSONALIZED_RECOMMENDATION_ENABLED,
        StorageNamespaces.SETTING, enabled)
    } catch (error) {
      console.debug(logTag, '保存个性化推荐设置失败: ' + PersonalizedSettingsPersist.describe(error))
    }
  }

  private static describe(error: Object): string {
    const message = (error as Error).message
    return message === undefined ? 'unknown' : message
  }
}

@Builder
export function PersonalizedSettingsPageBuilder(name: string, param: Object) {
  PersonalizedSettingsPage()
}

@Entry
@ComponentV2
struct PersonalizedSettingsPage {
  @Local
  private enablePersonalized: boolean = false
  @Local
  private personalizedSettingsPersist: PersonalizedSettingsPersist | null = null

  build() {
    NavDestination() {
      Column() {
        AboutSubpageHeader({ title: '个性化设置', subtitle: '腕上 RSS · 阅读体验' })
        Button({ type: ButtonType.Capsule }) {
          Row({ space: '10vp' }) {
            Column({ space: '2vp' }) {
              Text('个性化推荐')
                .fontSize('16fp')
                .fontWeight(FontWeight.Medium)
                .fontColor(DarkTheme.textPrimary)
              Text(this.enablePersonalized ? '已开启' : '已关闭')
                .fontSize('10fp')
                .fontColor(DarkTheme.textSecondary)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.enablePersonalized })
              .onChange((isOn: boolean) => {
                this.enablePersonalized = isOn
                console.debug(logTag, 'Component status:' + this.enablePersonalized)
                this.updatePersistState()
              })
          }
          .width('100%')
          .padding({ left: '17vp', right: '13vp' })
          .alignItems(VerticalAlign.Center)
        }
        .width('88%')
        .height('58vp')
        .backgroundColor('#D9262628')
        .border({ width: '0.5vp', color: '#3A3A3D' })
        .focusable(true)
        .focusOnTouch(true)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => {
          this.enablePersonalized = !this.enablePersonalized
          console.debug(logTag, 'Component status:' + this.enablePersonalized)
          this.updatePersistState()
        })

        Text('关闭后，应用将减少基于阅读偏好的内容推荐。')
          .width('72%')
          .margin({ top: '12vp' })
          .fontSize('10fp')
          .fontColor(DarkTheme.textSecondary)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .onAppear(async () => {
        this.personalizedSettingsPersist =
          await PersonalizedSettingsPersist.asyncInit(this.getUIContext().getHostContext() as Context)
        this.enablePersonalized = await this.personalizedSettingsPersist.isEnablePersonalized()
      })
    }
    .hideTitleBar(true)
    .linearGradient({ colors: DarkTheme.pageTopGradients.brand })
  }

  private updatePersistState() {
    if (this.personalizedSettingsPersist !== null) {
      if (this.enablePersonalized) {
        this.personalizedSettingsPersist.enablePersonalized()
      } else {
        this.personalizedSettingsPersist.disablePersonalized()
      }
    } else {
      this.getUIContext().getPromptAction().showToast({ message: "404-29" })
    }
  }
}
