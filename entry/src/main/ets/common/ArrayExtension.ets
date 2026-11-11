/**
 * 返回随机打乱顺序的数组副本（不修改原数组）
 * 使用 Fisher-Yates (Knuth) 洗牌算法
 */
export function shuffled<T>(array: readonly T[]): T[] {
  const result: T[] = array.slice(); // 创建副本

  for (let i: number = result.length - 1; i > 0; i--) {
    const j: number = Math.floor(Math.random() * (i + 1));

    // ArkTS 不支持解构赋值，使用临时变量交换
    const temp: T = result[i];
    result[i] = result[j];
    result[j] = temp;
  }

  return result;
}

/**
 * 从数组中随机返回一个元素
 * 如果数组为空，返回 null
 */
export function randomElement<T>(array: readonly T[]): T | null {
  if (array.length === 0) {
    return null;
  }
  const randomIndex: number = Math.floor(Math.random() * array.length);
  return array[randomIndex];
}