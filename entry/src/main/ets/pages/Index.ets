import { NavigationStack } from './NavigationStack/NavigationStack'

@Entry
@ComponentV2
struct Index {
  build() {
    Column() {
      NavigationStack()
    }
    .height($r('app.float.watch_screen_size_fp'))
    .width($r('app.float.watch_screen_size_fp'))
  }
}