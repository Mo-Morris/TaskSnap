# TaskSnap

TaskSnap 是一个 macOS 桌面悬浮任务备忘录，面向经常在多个 AI 会话、网页、代码窗口和文档之间切换的人。

它的核心思路是：把当前上下文保存成一张可见的任务卡片。截图可以直接拖进来，TaskSnap 会用 OpenAI-compatible 视觉模型读图并生成待办标题；也可以手动创建文字任务。每个任务还能继续写 Markdown 笔记，把「稍后再处理」真正变成可以找回的工作现场。

中文名称：**多任务并行备忘录**

![任务列表](docs/任务列表.png)

## 功能概览

| 模块 | 说明 |
| --- | --- |
| 截图任务 | 拖入 / 粘贴截图，自动生成任务卡片 |
| AI 视觉摘要 | 调用 OpenAI-compatible 视觉模型提炼标题与说明 |
| 手动任务 | 不依赖模型，快速创建文字待办 |
| 悬浮主窗口 | 始终置顶，可折叠为圆形浮窗 |
| 任务操作 | 拖拽完成 / 归档 / 排序，右键菜单编辑 |
| 任务笔记 | 多笔记、Markdown 编辑与预览、大纲导航 |
| 归档管理 | 查看历史任务，撤销归档或永久删除 |
| 菜单栏与快捷键 | 全局唤起主窗口、笔记窗口与常用操作 |
| 偏好设置 | 视觉模型配置、浅色 / 深色主题 |
| 本地存储 | 无需账号，数据保存在本机 |

## 截图任务

把屏幕上的上下文直接变成任务，而不是先复制、再切应用、再粘贴说明。

- 支持拖入截图、图片文件，或在 TaskSnap 窗口内按 `Command-V` 粘贴剪贴板图片
- 截图任务会自动进入列表顶部，并保留缩略图
- 点击缩略图可查看大图，快速回到当时的界面上下文
- 首次添加截图前，需要先在偏好设置中配置视觉模型

![拖动操作](docs/拖动操作.png)

## AI 视觉摘要

TaskSnap 支持 OpenAI-compatible 的视觉模型接口。配置完成后，截图任务会自动生成更自然的标题和背景说明。

偏好设置中需要填写：

- Endpoint
- API Key
- Model

保存配置时会先发起一次连通性测试。测试通过后，截图任务才会被接收并自动生成任务文案。接口地址可以填写服务根地址、`/v1` 地址或完整的 `/chat/completions` 地址，应用会自动补全为 Chat Completions 请求路径。

## 手动任务

不依赖模型也可以创建任务。点击任务列表顶部的 `+`，或通过菜单栏 / 折叠浮窗右键菜单选择「新建手动任务」，输入任务名称和描述即可。

手动任务会使用随机浅色卡片和系统图标标记，适合记录没有截图上下文的临时事项。

![多种任务类型](docs/多种任务类型.png)

## 悬浮主窗口

TaskSnap 主窗口保持在桌面前方，并可加入所有 Space，适合作为长期驻留的并行任务面板。

- **展开状态**：显示完整任务列表
- **折叠状态**：变成 72×72 的圆形任务图标，并显示进行中任务数量

在展开状态双击窗口顶部区域，或点击关闭按钮，会将窗口折叠而不是退出应用。折叠后点击图标即可重新展开。

折叠浮窗支持右键菜单，可直接打开任务笔记、归档管理、偏好设置等常用入口。

## 任务操作

TaskSnap 把「处理任务」设计成轻量、可视化的手势，而不是多层菜单。

- 点击任务文本打开对应任务笔记
- 拖动任意一张任务卡片，卡片会被「举起」浮在桌面上方，列表底部同时弹出投放区
  - 丢进「完成」即可标记完成；若任务已是完成状态，目标会切换为「恢复进行中」
  - 丢进「归档」即可归档，归档后只能在「归档管理」里找到
  - 没有丢进任何目标时，松手会按当前位置在列表里重新排序
- 右键任务卡片可查看笔记、编辑、完成 / 恢复、归档
- `Command-Shift-Delete` 可归档所有已完成任务

![移动任务操作](docs/移动任务操作.png)

## 任务笔记

每个任务都可以关联一份或多份 Markdown 笔记。点击任务文本，或通过菜单栏 / 折叠浮窗打开「任务笔记」窗口。

![任务笔记](docs/note-window-design.png)

### 笔记组织

- 左侧按任务标题快速切换，可折叠任务列表
- 支持「当前任务」与「全部任务」两种笔记范围
- 每个任务可创建多条笔记
- 支持本地笔记与外部 `.md` / `.markdown` 文件关联
- 侧边栏宽度可拖拽调整，窗口内容支持 `Command + / -` 缩放

### 编辑与预览

- 支持 Markdown 编辑和 Preview 两种模式
- 笔记自动保存到本地任务数据或关联文件
- 预览模式支持标题大纲、代码块复制、链接悬停高亮
- 支持标题、列表、引用、代码块、表格、分隔线、图片等 Markdown 渲染
- 顶部按钮可复制当前 Markdown 内容

## 归档管理

已完成或暂时不再处理的任务可以归档，避免主列表变得拥挤，同时保留完整上下文。

打开方式：

- 菜单栏 TaskSnap 图标 → 右键菜单 → 「归档管理…」
- 折叠浮窗右键菜单 → 「归档管理…」

归档页面提供：

- 左侧按归档时间展示所有归档任务
- 右侧展示选中任务的描述、来源、截图大图与 Markdown 笔记预览
- 「撤销归档」会把任务恢复为进行中，并放回主任务列表
- 「永久删除」会从本机数据中彻底移除任务

## 菜单栏与快捷键

TaskSnap 启动后会出现在 macOS 菜单栏。右键菜单栏图标，或使用全局快捷键，可在任意应用中快速唤起常用能力。

| 操作 | 入口 |
| --- | --- |
| 显示 / 隐藏主浮窗 | 菜单栏 → `Control-Shift-O` |
| 打开 / 隐藏任务笔记 | 菜单栏 → `Control-Shift-I` |
| 展开 / 收起任务列表 | 菜单栏 |
| 新建手动任务 | 菜单栏 |
| 归档管理 | 菜单栏 |
| 归档已完成任务 | 菜单栏 / `Command-Shift-Delete` |
| 偏好设置 | 菜单栏 / `Command-,` |

## 偏好设置

偏好设置窗口包含两类核心配置：

- **视觉模型**：Endpoint、API Key、Model，以及连通性测试
- **主题**：浅色 / 深色，影响主窗口、笔记窗口与设置界面

## 本地存储

TaskSnap 不依赖账号或云服务。任务、笔记与模型配置都会保存在当前用户的 Application Support 目录：

- `~/Library/Application Support/TaskSnap/tasks.json`
- `~/Library/Application Support/TaskSnap/vision-model.json`
- `~/Library/Application Support/TaskSnap/notes/`

## 适合什么场景

- 同时让多个 AI 工具执行任务，需要记住每个会话的上下文
- 调试、设计评审、文档整理等工作经常被中断，需要稍后回到现场
- 想用截图代替冗长描述，把临时任务先收起来
- 需要一个始终可见但不笨重的桌面待办面板

## 开发运行

要求：

- macOS 14 或更新版本
- Swift 6.1 或更新版本

运行：

```bash
swift run TaskSnap
```

测试：

```bash
swift test
```

打包 DMG：

```bash
./scripts/package-dmg.sh v0.1.0
```

脚本会构建 release 版本，并在临时目录中生成 `TaskSnap-<version>.dmg`。

### 升级安装

DMG 中包含 `Install.command`。升级时推荐双击运行它，脚本会覆盖安装到 `/Applications`、清除 macOS 下载隔离属性，并自动启动 TaskSnap。首次运行脚本时，如果 macOS 提示无法打开，请右键点击 `Install.command` 并选择「打开」。

如果手动拖拽 `TaskSnap.app` 到 `/Applications` 后仍遇到「无法验证开发者」提示，可以执行：

```bash
sudo xattr -dr com.apple.quarantine /Applications/TaskSnap.app
```

### 菜单栏图标诊断

TaskSnap 启动后会出现在 macOS 菜单栏右侧。如果看不到图标，可以按顺序检查进程和隔离属性：

```bash
pgrep -fl TaskSnap
xattr -l /Applications/TaskSnap.app
sudo xattr -dr com.apple.quarantine /Applications/TaskSnap.app
open /Applications/TaskSnap.app
sleep 2
pgrep -fl TaskSnap
```

如果最后一行能看到 TaskSnap 进程，但菜单栏仍没有图标，可能是菜单栏图标过多或 MacBook 刘海区域导致系统隐藏了部分状态项。

## 技术栈

- Swift Package Manager
- SwiftUI + AppKit
- Swift Testing
- OpenAI-compatible Chat Completions vision request
- Carbon HotKey / 菜单栏状态项

## License

MIT
