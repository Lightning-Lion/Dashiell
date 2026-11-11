/**
 * 线性插值函数
 * 将一个范围内的值映射到另一个范围
 *
 * @param inputMin 输入范围的最小值
 * @param inputMax 输入范围的最大值
 * @param outputMin 输出范围的最小值
 * @param outputMax 输出范围的最大值
 * @param inputValue 需要映射的输入值
 * @param clamp 是否将结果限制在输出范围内，默认为 false
 * @returns 映射后的输出值
 */
export function lerp(
  inputMin: number,
  inputMax: number,
  outputMin: number,
  outputMax: number,
  inputValue: number,
  clamp: boolean = false
): number {
  // 检查输入范围是否为零，防止除以零错误
  if (inputMin === inputMax) {
    return outputMin;
  }

  // 计算 inputValue 在输入范围内的归一化位置 (0 到 1 之间)
  let normalizedPosition = (inputValue - inputMin) / (inputMax - inputMin);

  // 如果需要裁剪，确保归一化位置在 0 到 1 之间
  if (clamp) {
    normalizedPosition = Math.max(0, Math.min(1, normalizedPosition));
  }

  // 使用归一化位置计算在输出范围内的值
  return outputMin + normalizedPosition * (outputMax - outputMin);
}

// 使用示例
// 将 0-100 范围内的 50 映射到 -1 到 1 范围内
// const result = lerp(0, 100, -1, 1, 50); // 返回 0

// 将超出范围的值 (150) 映射并裁剪到输出范围内
// const clampedResult = lerp(0, 100, -1, 1, 150, true); // 返回 1，因为被裁剪了