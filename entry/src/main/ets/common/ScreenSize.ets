// 本应用目前只适配了鸿蒙各款全智能手表：
// 华为Watch5、十周年款、华为Ultimate 2、非凡大师、华为Watch6
// 这几款手表屏幕是圆形，宽度高度一样
// 这几款手表有42mm、46mm，但是屏幕分辨率都是一样的
// 466×466
// 所以这里硬编码了这些值
// 华为保持分辨率不变，方便表盘设计师和开发者
// 但为了适配后续机型
// Ultimate 2、非凡大师
// 后续要逐步迁移到响应式布局。

// px是物理像素，vp是虚拟像素，fp是虚拟字体像素
export const watchSizePx: number = 466
export const watchSizeFp: number = 233
export const watchWidthFp: number = 233
export const watchWidthVp: number = 233
export const watchHeightFp: number = 233
export const watchHeightVp: number = 233

// 计算圆的内接正方形边长占圆直径的百分比，输出0-100
export const calculateSquareSidePercentage = () => {
  const percentage = (Math.sqrt(2) / 2) * 100;
  return percentage;
}

// 计算圆的内接正方形边长占圆直径的Unit，输出0-1
export const calculateSquareSideUnit = () => {
  const percentageUnit = (Math.sqrt(2) / 2);
  return percentageUnit;
}