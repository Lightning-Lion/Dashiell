/**
 * 生成随机的UUID字符串
 * 格式: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
 * 其中x是任意十六进制数字，y是8、9、A或B中的一个
 * @param lowercase 是否返回小写UUID (默认为true)
 * @return 生成的UUID字符串
 */
export function UUID(lowercase: boolean = true): string {
  let uuid = '';

  // 创建符合RFC4122版本4标准的UUID
  const template = lowercase ?
    'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx' :
    'XXXXXXXX-XXXX-4XXX-YXXX-XXXXXXXXXXXX';

  return template.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8); // 对于'y'位置，确保是8-B范围
    return (lowercase ? v.toString(16) : v.toString(16).toUpperCase());
  });
}
