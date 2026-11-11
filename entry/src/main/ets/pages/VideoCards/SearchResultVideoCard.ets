import { BilibiliService, BilibiliServiceWithoutLogin } from "../../common/BiliService";
import { VideoItem } from "../BiliHome/BiliHomeL2";
import { BaseVideoCard } from "./CommonVideo";

@ComponentV2
export struct SearchResultVideoCard {
  @Param @Require item: VideoItem;
  @Param @Require biliService: BilibiliService | BilibiliServiceWithoutLogin
  @Param @Require pageInfos: NavPathStack
  build() {
    BaseVideoCard({
      item:this.item,
      biliService:this.biliService,
      pageInfos:this.pageInfos
    })
  }
}