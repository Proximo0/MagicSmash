class_name UiTheme
extends RefCounted
## The one Theme the node-built screens share (market, letters, trade, board, bank): dark ground, bone text,
## dried-blood red for what is chosen, tallow gold for frames. Every built-in Control (Button, ItemList, Tree,
## LineEdit, TabBar, SpinBox, OptionButton, scroll bars) takes its look from here, and every one shows a gold
## frame when it has keyboard or controller focus, so a screen can be worked without a mouse.

static var _theme: Theme = null


static func shared() -> Theme:
	if _theme == null:
		_theme = _make()
	return _theme


static func _box(fill: Color, edge: Color, width: int = 1, pad: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(width)
	s.set_content_margin_all(pad)
	s.set_corner_radius_all(0)
	return s


static func _make() -> Theme:
	var t := Theme.new()
	t.default_font = UiKit.font()
	t.default_font_size = UiKit.px(14)
	var ink := Color(0.065, 0.054, 0.062, 0.98)
	var focus: StyleBoxFlat = _box(Color(0, 0, 0, 0), UiKit.GOLD, 2, 2)
	for c in ["Button", "OptionButton", "CheckBox"]:
		t.set_stylebox("normal", c, _box(Color(0.07, 0.058, 0.066), UiKit.GOLD_DIM, 1, 8))
		t.set_stylebox("hover", c, _box(Color(0.12, 0.09, 0.09), UiKit.GOLD, 1, 8))
		t.set_stylebox("pressed", c, _box(Color(0.16, 0.05, 0.05), UiKit.GOLD, 1, 8))
		t.set_stylebox("disabled", c, _box(Color(0.05, 0.045, 0.05), Color(0.3, 0.28, 0.25), 1, 8))
		t.set_stylebox("focus", c, focus)
		t.set_color("font_color", c, UiKit.BONE)
		t.set_color("font_hover_color", c, UiKit.GOLD)
		t.set_color("font_focus_color", c, UiKit.GOLD)
		t.set_color("font_pressed_color", c, UiKit.BONE)
		t.set_color("font_disabled_color", c, Color(0.4, 0.38, 0.34))
	t.set_color("font_color", "Label", UiKit.BONE)
	t.set_color("font_color", "RichTextLabel", UiKit.BONE)
	t.set_color("default_color", "RichTextLabel", UiKit.BONE)
	for c in ["LineEdit", "TextEdit", "SpinBox"]:
		t.set_stylebox("normal", c, _box(Color(0.03, 0.026, 0.034), UiKit.GOLD_DIM, 1, 6))
		t.set_stylebox("focus", c, _box(Color(0.03, 0.026, 0.034), UiKit.GOLD, 2, 6))
		t.set_stylebox("read_only", c, _box(Color(0.05, 0.045, 0.05), Color(0.3, 0.28, 0.25), 1, 6))
		t.set_color("font_color", c, UiKit.BONE)
		t.set_color("caret_color", c, UiKit.GOLD)
		t.set_color("selection_color", c, UiKit.BLOOD)
		t.set_color("font_placeholder_color", c, UiKit.BONE_DIM)
	for c in ["ItemList", "Tree"]:
		t.set_stylebox("panel", c, _box(Color(0.04, 0.034, 0.042), UiKit.GOLD_DIM, 1, 4))
		t.set_stylebox("focus", c, _box(Color(0, 0, 0, 0), UiKit.GOLD, 2, 0))
		t.set_color("font_color", c, UiKit.BONE)
		t.set_color("font_selected_color", c, UiKit.GOLD)
		t.set_color("guide_color", c, Color(UiKit.GOLD_DIM, 0.3))
	t.set_stylebox("selected", "ItemList", _box(UiKit.BLOOD, UiKit.GOLD, 1, 2))
	t.set_stylebox("selected_focus", "ItemList", _box(UiKit.BLOOD_BRIGHT, UiKit.GOLD, 2, 2))
	t.set_stylebox("cursor", "ItemList", _box(Color(0, 0, 0, 0), UiKit.GOLD_DIM, 1, 2))
	t.set_stylebox("cursor_unfocused", "ItemList", _box(Color(0, 0, 0, 0), UiKit.GOLD_DIM, 1, 2))
	t.set_stylebox("selected", "Tree", _box(UiKit.BLOOD, UiKit.GOLD, 1, 2))
	t.set_stylebox("selected_focus", "Tree", _box(UiKit.BLOOD_BRIGHT, UiKit.GOLD, 2, 2))
	t.set_stylebox("cursor", "Tree", _box(Color(0, 0, 0, 0), UiKit.GOLD, 1, 2))
	t.set_stylebox("cursor_unfocused", "Tree", _box(Color(0, 0, 0, 0), UiKit.GOLD_DIM, 1, 2))
	t.set_color("title_button_color", "Tree", UiKit.GOLD)
	t.set_stylebox("title_button_normal", "Tree", _box(Color(0.09, 0.07, 0.07), UiKit.GOLD_DIM, 1, 3))
	t.set_stylebox("title_button_hover", "Tree", _box(Color(0.09, 0.07, 0.07), UiKit.GOLD_DIM, 1, 3))
	t.set_stylebox("title_button_pressed", "Tree", _box(Color(0.09, 0.07, 0.07), UiKit.GOLD_DIM, 1, 3))
	t.set_stylebox("tab_selected", "TabBar", _box(UiKit.BLOOD, UiKit.GOLD, 1, 8))
	t.set_stylebox("tab_unselected", "TabBar", _box(Color(0.07, 0.058, 0.066), UiKit.GOLD_DIM, 1, 8))
	t.set_stylebox("tab_hovered", "TabBar", _box(Color(0.12, 0.09, 0.09), UiKit.GOLD, 1, 8))
	t.set_stylebox("tab_focus", "TabBar", focus)
	t.set_stylebox("tab_disabled", "TabBar", _box(Color(0.05, 0.045, 0.05), Color(0.3, 0.28, 0.25), 1, 8))
	t.set_color("font_selected_color", "TabBar", UiKit.BONE)
	t.set_color("font_unselected_color", "TabBar", UiKit.BONE_DIM)
	t.set_color("font_hovered_color", "TabBar", UiKit.GOLD)
	t.set_stylebox("panel", "PopupMenu", _box(ink, UiKit.GOLD, 1, 4))
	t.set_stylebox("hover", "PopupMenu", _box(UiKit.BLOOD, UiKit.GOLD, 1, 2))
	t.set_color("font_color", "PopupMenu", UiKit.BONE)
	t.set_color("font_hover_color", "PopupMenu", UiKit.GOLD)
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.045, 0.036, 0.045, 0.98), UiKit.GOLD_DIM, 1, 8))
	for c in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", c, _box(Color(0.03, 0.026, 0.034), Color(0, 0, 0, 0), 0, 0))
		t.set_stylebox("grabber", c, _box(UiKit.GOLD_DIM, UiKit.GOLD_DIM, 0, 0))
		t.set_stylebox("grabber_highlight", c, _box(UiKit.GOLD, UiKit.GOLD, 0, 0))
		t.set_stylebox("grabber_pressed", c, _box(UiKit.GOLD, UiKit.GOLD, 0, 0))
	return t
