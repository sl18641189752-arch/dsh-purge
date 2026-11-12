# dsh-purge

> macOS 磁盘分级清理工具：把「删什么」按风险分成四档，D 档（你的数据）永不触碰。

一个开发者机器上，磁盘真正被吃掉的往往不是项目代码，而是**能删但没人删**的东西——npm 缓存、uv 缓存、应用日志、跑不动的本地模型权重。`dsh-purge` 把这些按"删了会怎样"分成四档，让你一眼看清 10 秒能回收多少空间，而不用在一个 200G 的目录树里猜。

## 为什么不是 `rm -rf ~/Library/Caches/*`

因为那是一次性、不可审计、也无法复用的动作。真正的问题不是"这次怎么腾出空间"，而是"三个月后它又满了、我还得再来一次"。

`dsh-purge` 给的是：

1. **分级**：A/B 零风险、C 需重新下载、D 是你的数据（工具无条件拒绝处理）
2. **默认可预览**：不加 `--yes` 只统计不删
3. **可定时**：`install.sh` 注册 launchd，每周自动跑 A+B

## 档位

| 档位 | 内容 | 删了会怎样 |
|---|---|---|
| **A** 可再生缓存 | `~/.npm/_cacache`、`~/.npm/_npx`、`~/.cache/uv`、`~/Library/Caches`、`~/Library/Developer/{CoreSimulator,Xcode/DerivedData}`、pnpm/yarn/bun store | 下次构建重新下载，零风险 |
| **B** 日志 | WorkBuddy / CodeBuddy 应用日志、`~/Library/Logs`、`~/.npm/_logs` | 应用自动重建 |
| **C** 模型权重 | `~/.ollama/models`、`~/.cache/huggingface`、`~/.cache/models`、whisper（保留 `medium.pt`） | 需要重新下载 |
| **D** 个人数据 | 项目目录、聊天记录、容器数据、WorkBuddy 工作区 | **工具永不删除**，只列清单供人工确认 |

## 安装

```bash
git clone https://github.com/sl18641189752-arch/dsh-purge.git
cd dsh-purge
chmod +x purge.sh install.sh
./install.sh                 # 每周日 03:00 自动清理 A+B
```

安装器会把脚本复制到 `~/.dsh/bin/`，并注册 launchd 任务 `com.dshpurge.weekly`。

原因：macOS 的 TCC 会拒绝后台 launchd 任务访问 `~/Documents`，直接在文档目录里运行会得到 `Operation not permitted`。

### 安装器选项

```bash
./install.sh --tier abc       # 定时任务也清模型权重
./install.sh --daily          # 每天 03:00，而非每周
./install.sh --off            # 只装脚本，不注册定时任务
./install.sh --uninstall      # 卸载
./install.sh --dry-run        # 只打印将执行什么
```

## 使用

```bash
# 先看能清多少（默认就是统计模式，不会删）
~/.dsh/bin/dsh-purge.sh

# 清缓存 + 日志
~/.dsh/bin/dsh-purge.sh --tier ab --yes

# 清模型权重，并写日志
~/.dsh/bin/dsh-purge.sh --tier c --yes --log /tmp/purge.log

# 看看 D 档有哪些个人数据（永不删除）
~/.dsh/bin/dsh-purge.sh --manifest d
```

## 安全模型

- 不加 `--yes` **绝不删除**任何文件
- D 档没有任何删除代码路径，只有一份清单打印
- 内置路径护栏：拒绝 `/` 和 `$HOME` 本身
- whisper 模型只清 `tiny/base/small`，保留 `medium.pt`（转写常用档）
- 正在被占用的文件会删除失败并计入"失败项"，不影响其余清理
- 沙箱环境（如 AI 编码代理）中删除家目录外文件需要额外授权，脚本不会绕过

## 实测

在一台 228G 的 M1 Mac 上，A+B+C 一次回收 **26G**（可用空间 26G → 52G），耗时约 2 分钟，其中 `~/.ollama/models` 占 11G。

## 环境要求

- macOS（launchd 定时部分）；`purge.sh` 主体在 Linux 上也可用，只是 `install.sh` 不适用
- `bash` 3.2+（macOS 自带），无其他依赖

## 开发

```bash
bash -n purge.sh install.sh    # 语法检查
shellcheck purge.sh install.sh # 建议
```

CI 会对每次提交跑 `bash -n` 和 shellcheck。

## 许可

MIT
