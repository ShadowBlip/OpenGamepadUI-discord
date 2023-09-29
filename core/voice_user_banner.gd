extends Control

signal removed

@export var texture: Texture2D
@export var text: String
@export var normal_frame_color := Color(0.1, 0.1, 0.1)
@export var talking_frame_color := Color(0.31, 0.98, 0.48)

@onready var panel := $%PanelContainer as PanelContainer
@onready var avatar := $%TextureRect as TextureRect
@onready var label := $%Label as Label
@onready var fade_effect := $FadeEffect as FadeEffect


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	avatar.texture = texture
	label.text = text
	set_frame_color(normal_frame_color)


func set_frame_color(color: Color) -> void:
	var panel_style = panel.get("theme_override_styles/panel")
	panel_style.set("border_color", color)


func set_talking(is_talking: bool) -> void:
	if is_talking:
		set_frame_color(talking_frame_color)
		return
	
	set_frame_color(normal_frame_color)


func remove() -> void:
	removed.emit()
	await fade_effect.fade_out_finished
	queue_free()
