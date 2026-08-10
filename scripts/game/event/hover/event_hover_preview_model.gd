class_name EventHoverPreviewModel
extends RefCounted

## 只读悬停预览的数据模型，不持有棋盘节点或事件节点引用。
var visible: bool = false
var title: String = ""
var type_label: String = ""
var stat_lines: Array[String] = []
var reward_lines: Array[String] = []
var ability_lines: Array[String] = []
