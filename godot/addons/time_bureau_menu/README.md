# Time Bureau Menu / 时空管理局主界面

Godot 4.5.1 GDScript 模块。复制整个文件夹到 `res://addons/time_bureau_menu`；入口是 `main_menu.tscn`。资产、字体和设置视图均在本目录内。

将入口实例加入覆盖视口的 Control 或 CanvasLayer，随后连接：

- `new_game_requested`：宿主释放旧的一局，并创建新的游戏场景。
- `quit_requested`：宿主调用 `get_tree().quit()`。
- `settings_changed(values)`：宿主应用 `master_volume`（float，0～1）和 `fullscreen`（bool）。
- `settings_opened`：内置设置页面已打开。

同步设置用 `set_settings(dictionary)`，不会触发变更信号。读取用 `get_settings()`，返回副本。`show_main_menu()` 显示三个入口；`open_settings()` / `close_settings()` 进入或离开设置；`hide()` / `queue_free()` 隐藏或释放。

模块不修改宿主场景、InputMap、Autoload、音量、窗口或存档。它只显示 UI 并发信号。背景完整等比显示，兼容 320×240 及以上尺寸；保持父节点全屏且不裁剪菜单。

要允许直接删除整个目录，宿主用 `ResourceLoader.exists(path)` 检查后动态 `load(path)`，目录不存在时进入宿主原流程。避免在其他场景中硬引用或 `preload` 本模块。卸载时释放实例，删除本目录即可；信号连接随节点自动清理。

根目录的 `使用与接入说明.md` 含完整说明和可直接采用的接入代码。`example/demo_host.gd` 演示了开始新游戏、设置应用、退出和模块缺失的回退流程。
# Game 工程接入补充（2026-10-24）

本目录从 T13 的独立菜单复制而来，保留原背景、信号和设置接口。新增
`add_settings_action(caption: String, callback: Callable) -> Button`：宿主追加设置入口，
返回按钮可独立指定字体；模块仍不依赖 Keybinds、Timeline 或 World。
紧凑窗口中同时压缩设置控件高度，支持追加入口后在 320×240 下使用。

真实宿主为 `res://scripts/main_menu_host.gd`，场景为 `res://scenes/main_menu.tscn`。
宿主动态加载本模块，删除本目录后会直接进入原来的 World。
工程结构、数据流和验证结果见项目根目录上一层的《架构分析与主界面接入说明.md》。

