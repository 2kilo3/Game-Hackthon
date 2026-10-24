extends Node
## 平行时空：现代 / 未来。用 R 键切换（Keybinds 里的 switch_time）。
##
## - 全局只有一个"当前时空"，UI 和地面都读这里
## - 切换时发 era_changed 信号，世界和 HUD 各自响应（换路面、换标签）

enum Era { MODERN, FUTURE }

signal era_changed(era: int)

var era: int = Era.MODERN

func era_name() -> String:
	return "现代" if era == Era.MODERN else "未来"

func is_future() -> bool:
	return era == Era.FUTURE

func toggle() -> void:
	era = Era.FUTURE if era == Era.MODERN else Era.MODERN
	era_changed.emit(era)

func set_era(value: int) -> void:
	if value != Era.MODERN and value != Era.FUTURE:
		return
	if value == era:
		return
	era = value
	era_changed.emit(era)

## 重开 / 复活时回到现代（可选，默认保持当前时空）
func reset() -> void:
	set_era(Era.MODERN)
