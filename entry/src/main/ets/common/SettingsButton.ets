import { common } from '@kit.AbilityKit';
import { ArcButton, ArcButtonOptions, ArcButtonPosition, ArcButtonStyleMode, ColorMetrics } from '@kit.ArkUI';

export function openNetworkSettings(context: common.UIAbilityContext): Promise<void> {
  return context.startAbility({
    bundleName: 'com.huawei.hmos.settings',
    abilityName: 'com.huawei.hmos.settings.ExternalWlanAbility'
  });
}

@ComponentV2
export struct SettingsButton {
  // 不传颜色时保持系统默认样式的蓝色 ArcButton；传入后改用 CUSTOM，跟调用页的配色走。
  @Param arcBackgroundColor?: ColorMetrics = undefined
  @Param arcFontColor?: ColorMetrics = undefined
  @Param arcShadowColor?: ColorMetrics = undefined

  build() {
    ArcButton({
      options: new ArcButtonOptions({
        label: "设置网络",
        position: ArcButtonPosition.BOTTOM_EDGE,
        styleMode: this.arcBackgroundColor !== undefined ? ArcButtonStyleMode.CUSTOM : ArcButtonStyleMode.EMPHASIZED_LIGHT,
        backgroundColor: this.arcBackgroundColor,
        fontColor: this.arcFontColor,
        shadowColor: this.arcShadowColor,
        shadowEnabled: this.arcShadowColor !== undefined,
        onClick: () => {
          const uiAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
          openNetworkSettings(uiAbilityContext).catch(() => console.warn('Network settings unavailable'));
        }
      })
    })
  }
}