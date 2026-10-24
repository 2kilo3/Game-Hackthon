# 衍月与特斯拉对话模块（Godot 4）

复制整个 `addons/bureau_dialogue` 目录到项目即可使用；无 Autoload、无输入映射依赖。当前工程由 `scripts/dialogue_host.gd` 监听游戏事件，被动播放 `scripts/story_dialogue.gd` 中的正式剧情。正文依据 Game/文档/交互剧情_用户补充原稿.md 修订，实际台词见 Game/文档/交互剧情_修订稿.md；原 F8 入口已移除。

## 文件与接口

- `dialogue.tscn`：可实例化 CanvasLayer，层级 80。
- `dialogue.gd`：界面、输入、会话和暂停状态。
- `assets/yanyue_full.png`：用户原始透明立绘的完整副本。
- `assets/tesla_full.png`：根据用户 JPG 通过 ImageGen 清理背景的透明版本。
- `assets/dialogue_sans.ttf`、`OFL.txt`：独立中文字体，覆盖基本汉字和扩展 A，不依赖宿主字体。

```gdscript
var dialogue = load("res://addons/bureau_dialogue/dialogue.tscn").instantiate()
add_child(dialogue) # ready 完成后调用
dialogue.open_dialogue([
    {"speaker": "特斯拉", "text": "干得不错，看看他身上有什么有价值的东西"},
])
# dialogue.advance()        # 下一句；最后一句后关闭
# dialogue.close_dialogue() # 提前关闭；可重复调用
```

| 接口 | 输入与返回 |
|---|---|
| `open_dialogue(lines, resources={}, names={}) -> bool` | `lines: Array`，每句为 `{speaker: String, text: String}`。有效内容打开成功返回 true。|
| `resources: Dictionary` | 键为 `衍月` / `特斯拉`。值可为 Texture2D（含 AtlasTexture）或有效资源路径。省略键使用内置立绘；显式 null、缺失路径或无效值显示角色占位文字。自定义纹理按传入画面完整显示。|
| `names: Dictionary` | 可选角色显示名，例如 `{"特斯拉": "博士"}`；不会改变角色定位和高亮 ID。|
| `advance() -> bool` | 打开时推进一次并返回 true；关闭时无操作返回 false。|
| `close_dialogue()` | 清空会话并恢复打开前的暂停状态；重复关闭不再发信号。|
| `is_open() -> bool` | 当前是否打开。|
| `current_index() -> int` | 当前句子从 0 开始计数；关闭时 -1。|
| `current_line() -> Dictionary` | 当前句子的副本；关闭时空字典。|

信号：`opened()`、`line_changed(speaker, text, index)`、`closed()`、`finished()`。`finished` 仅在推进完最后一句时发出；Esc、关闭按钮或空输入关闭只发 `closed`。结束顺序为关闭并恢复状态 → `closed` → `finished`，可在 `finished` 回调直接打开下一段对话。

## 状态与边界

`_lines` 保存规范化后的独立数据，调用者修改原数组或读取结果不会影响播放。非法条目、非字符串文本和空白文本被跳过；全部无效时关闭并返回 false。未知说话人作为旁白处理，两侧均变暗；两名角色切换时，当前角色亮度 1.0，另一方 0.38，透明通道保持。

首次打开保存 `_pause_before`，设 SceneTree.paused=true；打开状态下再次打开仅替换内容、回到第 0 句，不覆盖最初的暂停快照。关闭恢复快照，因此原先已暂停时仍保持暂停。移除打开的节点也会恢复暂停状态。请不要让其他系统在对话期间直接改写 `SceneTree.paused`，应由宿主协调模态界面。

CanvasLayer 以 ALWAYS 模式接收 Enter / 小键盘 Enter / Space 推进、Esc 关闭；键盘事件在 `_input` 消费，避免一次按键既推进又激活按钮。按钮支持鼠标和键盘焦点。长文本自动换行并可滚动；面板水平居中，底边距 12 个逻辑像素；立绘置于面板两侧上方。内置立绘用 AtlasTexture 裁取透明内容包围盒顶部 49%，不修改源图。

标准暂停只冻结遵循 SceneTree 暂停的节点。当前游戏的完美格挡会临时令 Player 为 ALWAYS，所以接入层在 opened 时保存并禁用 Player.process_mode，关闭或移除模块时恢复。对话中暂停 Boss 变身、能量桩启动和 Boss 硬直等待使用的 SceneTreeTimer 已设置 `process_always=false`。移植到其他项目时，应同样协调自己的 ALWAYS 游戏逻辑和不受暂停控制的计时器。

## 当前游戏接入与移除

`World/DialogueHost` 动态加载模块，缺少模块文件时直接跳过。`open_dialogue(lines, resources, names)` 接口保持不变。正式剧情经 `queue_story(id)` 排队、按每局一次去重；仅在游戏未暂停、玩家存活、穿梭和死亡回溯完成后播放。对话期间 Tab 不影响天赋界面。程序接口仍允许覆盖已有暂停界面，关闭时还原其暂停状态。

最新触发条件、修订对照与逐项验证见 Game/剧情补全与结局说明.md。Esc/关闭按钮仍可跳过当前会话，下一段排队剧情在后续帧播放；跳过的段落本局不重播。新 World 重置剧情记录，死亡回溯不重置。开局自动播放战前与进战对白，现代 Boss 正常走出后播放登场剧情。结尾关闭前若尚未读到“未完待续”，会先显示这一幕；继续后淡出到独立的黑屏“游戏结束”场景，Enter / Esc 可返回主菜单。

完整移除对话功能：删除 `World/DialogueHost` 节点及其 ext_resource、`scripts/dialogue_host.gd`、`scripts/story_dialogue.gd` 和本模块目录。TalentMenu 使用可空节点查询，世界与战斗脚本仅发出事件信号，因此移除后仍能工作。仅删除模块目录也可正常运行游戏，无对话播放。

推荐宿主画布最小 320×240。本项目以 720×405 逻辑画布运行、默认窗口 1440×810。超出字体覆盖范围的少数生僻字，应换用完整中文字体。

## 素材来源

衍月来自 `E:/AI+游戏黑客松/T14/衍月.png`，字节保持一致。特斯拉源图为同目录 `特斯拉.jpg`；使用内置 ImageGen 的编辑模式、透明背景输出，要求保留人物、服装、姿态并清理白色背景，随后保存为 `assets/tesla_full.png`。这是生成式透明版本，人物细节有重绘，不应称为无损抠图。原 JPG 未覆盖。参考布局草图仅用于理解排布，未作为游戏纹理。

字体由 Noto Sans SC 的 400 字重制作子集并重命名为 Bureau Dialogue Sans；原许可见 `assets/OFL.txt`。发布时保留许可文件。
