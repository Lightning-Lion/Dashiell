/**
 * 应用级日志标识 / App-specific log identity.
 *
 * 这是共享日志运行时里唯一允许按 App 不同的配置:
 *  - appName: 生成文件头、导出日志头使用;
 *  - defaultTag: 调用方没传 tag 时的兜底 hilog tag。
 *
 * 其他 Log* 文件必须与手表端仓库保持逐字节一致,改这里以外的内容前先读
 * docs/logging.md "共享文件与允许差异"。
 */
export class LogAppConfig {
  static readonly appName: string = 'Dashiell';
  static readonly defaultTag: string = 'Dashiell';
}
