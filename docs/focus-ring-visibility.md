# 键盘焦点环（focus ring）：原因与修复

本文记录 Markdown Preview 的焦点环策略、rebase 后焦点环“全面回归”的原因，
以及最终的修复方式。

- 相关提交：`4ea77f2`、`bef59d8`、`31c1c9c`（原始修复），`971e244`（本次修复）
- 核心文件：`md-preview/Helpers/FocusRingVisibility.swift`

## 1. 目标行为

macOS 会在持有键盘焦点的控件周围画焦点环。它的问题在于**触发时机**：

- 视图出现时程序化地把焦点放到某个控件上；
- 鼠标点击让控件获得焦点（SwiftUI 的 `Button`、`NSSegmentedControl`、
  文本框等都会）；
- 用键盘 Tab 导航。

前两种情况是纯指针操作，画焦点环会让界面显得“跳”。因此应用的目标是：

> 鼠标操作时保持安静；只有用户真正用键盘移动焦点时才显示焦点环。

## 2. 实现结构

### 2.1 单一状态源

`FocusRingVisibility` 是一个 `@Observable @MainActor` 单例，只维护一个信号：

```swift
private(set) var isKeyboardActive = false
```

它在初始化时安装两类监听：

| 监听 | 作用 |
| --- | --- |
| `NSEvent.addLocalMonitorForEvents` | 观察 `keyDown` 和三种鼠标按下事件 |
| `NSWindow.didBecomeKeyNotification` | 新窗口/弹窗出现后重新套用策略 |

`reset()` 在启动和每次打开 Settings 时把状态置回 `false`，避免“用快捷键打开的
窗口”第一帧就带环。

### 2.2 两条渲染路径

焦点环并不只由一处绘制，因此策略也要覆盖两套体系。

**SwiftUI**：每个 SwiftUI hosting root 都套一层
`.hidesFocusRingUntilKeyboard()`：

```swift
content.focusEffectDisabled(!visibility.isKeyboardActive)
```

覆盖的位置包括 Settings 各面板、Inspector、主题弹窗、分享面板、格式化工具栏的
各个 popover、收藏夹提示和更新胶囊。

**AppKit**：`AppKitFocusRingPolicy` 遍历 `NSApp.windows` 的 `contentView`，
对以下控件切换 `focusRingType`：

- `NSButton`
- `NSSegmentedControl`
- `NSTextField`（以及编辑期间的 field editor）
- `NSTableView` / `NSCollectionView`

每个控件第一次被处理时，用 associated object 记住它原本的 `focusRingType`；
键盘态恢复原值，指针态设为 `.none`。

## 3. rebase 之后发生了什么

排查结论是：**rebase 没有丢失任何修复。**

用 `git range-diff` 对比 rebase 前后的分支：

- `4ea77f2` → `4ea77f2`、`bef59d8` → `bef59d8`、`31c1c9c` → `31c1c9c`
  三个提交的补丁逐字节一致；
- 只有 3 个 editor 提交被跳过，因为新的 main 已通过 `#651` 合入了同一功能。

运行时也验证了策略本身是工作的。用 lldb 读取运行中实例的控件状态：

```
点击            → focusRingType = 1 (.none)
Tab             → focusRingType = 0 (.default)
再次点击        → focusRingType = 1 (.none)
```

同时直接读取运行实例中的 `isKeyboardActive`，发现它是 **`true`**——而这是唯一
会让焦点环显示的取值。所以问题不在“修复是否存在”，而在“什么时候把状态设为
true”。

## 4. 根因

旧的事件处理把**任何 `keyDown`** 都当成“用户开始用键盘导航”：

```swift
let keyboard = event.type == .keyDown
isKeyboardActive = keyboard
```

而实际上大量按键并不移动焦点：

- 在编辑器里打字（新 main 的纯文本源码模式让打字成为高频操作）；
- 空格、方向键、Page Up/Down 滚动文档；
- 命令快捷键，例如 `⌘E`、`⌘F`、`⌘C`，以及 main 新增的 `⇧⌘E`
  源码/富文本切换。

只要按下其中任意一个键，全局标志就变成 `true`，所有 SwiftUI root 的
`focusEffectDisabled` 被关闭、所有 AppKit 控件恢复原本的环样式。之后只要还有
控件持有焦点，焦点环就一直可见，直到下一次鼠标点击才被清除。

于是纯鼠标用户也会看到“所有位置都有焦点环”——看起来像修复被 rebase 吃掉了，
实际上是“打一次字/按一次快捷键”把全局开关打开了。

## 5. 解决方案

把“键盘态”的判定收窄为**真正移动焦点的键**：Tab 家族（含 Shift-Tab、
Control-Tab），它们使用同一个 key code `48`。

```swift
private func note(_ event: NSEvent) {
    switch event.type {
    case .keyDown:
        guard Self.movesFocus(event), !isKeyboardActive else { return }
        isKeyboardActive = true
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
        let wasKeyboardActive = isKeyboardActive
        isKeyboardActive = false
        if wasKeyboardActive {
            // 在事件分发前关掉，点击自身的焦点变化就不会画环
            AppKitFocusRingPolicy.apply()
        }
        // 分发后再套用一次，覆盖这次点击新建的控件（例如弹出的 popover）
        DispatchQueue.main.async { MainActor.assumeIsolated { AppKitFocusRingPolicy.apply() } }
        return
    default:
        return
    }
    // Tab 在事件分发前恢复环样式，确保新获得焦点的控件来得及画出来
    AppKitFocusRingPolicy.apply()
    DispatchQueue.main.async { MainActor.assumeIsolated { AppKitFocusRingPolicy.apply() } }
}

private static func movesFocus(_ event: NSEvent) -> Bool {
    event.keyCode == 48   // Tab / Shift-Tab / Control-Tab
}
```

行为变化：

| 输入 | 修复前 | 修复后 |
| --- | --- | --- |
| 鼠标点击 | 隐藏环 | 隐藏环（不变） |
| 打字 / 滚动键 / 快捷键 | **显示环** | 保持当前状态 |
| Tab / Shift-Tab | 显示环 | 显示环（不变） |

## 6. 验证

Debug 构建后，用 lldb 直接读 AppKit 控件的 `focusRingType`，不依赖肉眼判断：

1. 启动并套用策略后：`.none`；
2. 发送字母键：仍为 `.none`（旧实现会变成 `.default`）；
3. 发送 Tab：变为 `.default`；
4. 发送鼠标点击：回到 `.none`。

该文件只有 AppKit/SwiftUI 侧行为，没有现成的单元测试覆盖；验证依赖构建与运行时
检查。

## 7. 已知边界

- 只用**方向键**在列表/工具栏中移动焦点不会重新显示焦点环；选中高亮仍然可见。
  若需要让方向键也算导航，只需扩展 `movesFocus`。
- 程序化设置焦点（例如 Settings 打开时聚焦当前选项）仍受同一个全局标志控制：
  点击后不显示，Tab 后显示。
- 策略以窗口为单位遍历 `contentView`；新窗口由 `didBecomeKey` 补套用。
