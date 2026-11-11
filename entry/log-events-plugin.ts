import { HvigorPlugin } from '@ohos/hvigor';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import process from 'node:process';

/**
 * 构建期生成日志事件 / Generate log events before PreBuild.
 *
 * 挂到 entry 模块的 PreBuild 之前:
 *  - 扫描 entry/src/main/ets 下所有 .ets 的 LogEvents.<name>(...)
 *  - 读取 logging/events.json
 *  - 重写 utils/log/LogEvents.generated.ets(含精确 file:line:column/class/method)
 *
 * 生成失败会让构建失败,避免把过期行号带进 HAP。
 */
export function logEventsPlugin(): HvigorPlugin {
  return {
    pluginId: 'dashiell-log-events',
    apply(node): void {
      node.registerTask({
        name: 'GenerateDashiellLogEvents',
        run: (): void => {
          const moduleDir: string = node.getNodePath();
          const root: string = resolve(moduleDir, '..');
          execFileSync(process.execPath, [resolve(root, 'tools/log-gen/cli.mjs'), '--write', '--app', 'Dashiell'], {
            cwd: root,
            stdio: 'inherit',
          });
        },
        postDependencies: ['default@PreBuild'],
      });
    },
  };
}
