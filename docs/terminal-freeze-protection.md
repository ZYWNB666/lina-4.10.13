# 终端后台冻结保护

## 构建与行为

按原来的 Dockerfile 构建并部署 Web 镜像即可；本次没有修改线上 Pod。
Luna 来自官方 `jumpserver/web:v5.0.0-ce`，因此保护脚本在最终镜像阶段注入，
不是放进仅供管理界面使用的 Lina bundle。根工作台、独立连接页及 HTML fallback
都会在应用启动之前同步加载脚本。脚本文件名带内容哈希，避免更新后读到旧缓存。

`utils/luna-terminal-session-guard.js` 仅跟踪 `/koko/ws/terminal` 及其尾斜线形式。
每个连接从 CONNECTING 阶段申请一个 shared Web Lock，关闭时释放。
所有标签、所有连接使用共享模式，互不排队；一个连接关闭不会解除其他连接的保护。
申请尚未完成就断线时取消请求。没有相关连接的页面不会持有锁。
脚本不会刷新页面、重连、修改协议、读取终端内容或记录令牌。
不支持 Web Locks 或申请失败时，保留原有终端行为，并输出不含凭据的警告。

当前 Chromium 的自动冻结策略把持有 Web Lock 视作不能冻结的原因。
这是针对后台自动冻结的兼容措施，不是浏览器保证永不终止页面的 API。
它不保留关闭页面、同标签导航离开、浏览器退出、系统休眠或真实网络故障后的 SSH 会话。
Koko 的断线会话保留机制不在本次改动内。

已删除 Dockerfile 中原来的 unload / pageshow 自动刷新注入。
HTML 的 no-store 和原有代理超时配置继续保留；no-store 本身不能阻止后台冻结。

## 上线后验证

1. 使用没有 `BackForwardCacheForWebSocketsAllowed=false` 策略的测试浏览器。
   在 `chrome://policy` 或 `edge://policy` 确认策略状态；只用测试环境移除策略，
   不要通过关闭正在运行重要任务的浏览器来做切换。
2. 新开终端页，连接测试资产。旧的已打开页面不会自动获得新脚本。
3. 在终端所在页面的 Console 执行：

   ```js
   JSON.stringify(window.__jmsTerminalSessionGuard)
   ```

   连接建立后应看到 `supported:true`、`activeSockets` 和 `heldLocks` 大于 0，
   `failures:0`。无终端连接时计数为 0。持锁数统计 WebSocket，而非 UI 终端面板数量。
4. 在测试资产运行一个可中断的计数/等待任务，记录原会话 ID 和进程 ID。
   切到其他浏览器标签，至少等待 10 分钟并覆盖此前复现间隔，然后返回。
   应保持原会话和原进程，不应重新登录、刷新、重建会话或出现 1006。
   Chrome 和 Edge 分别执行，保留当时的浏览器版本和节能/休眠设置。
5. 打开多个终端，关闭一个时其他连接仍持锁；全部关闭后
   `activeSockets:0`、`heldLocks:0`。检查 Koko 日志没有对应会话被结束。

`chrome://discards` 可辅助查看自动冻结资格；手动强制 Freeze/Discard 会绕过
正常资格判断，不应将强制操作是否成功当成 Web Lock 自动冻结保护的验收标准。

## 开发检查

```sh
node --test utils/luna-terminal-session-guard.test.cjs
sh -n utils/install-luna-terminal-guard.sh
yarn lint
yarn build:prod
```

单元测试覆盖锁生命周期与 WebSocket 包装兼容性；它不能代替真实浏览器后台验证。

依据：
- https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/performance_manager/freezing/freezing_policy.cc
- https://developer.chrome.com/blog/freezing-on-energy-saver
