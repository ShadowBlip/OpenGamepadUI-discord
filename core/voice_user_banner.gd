extends Control

@export var texture: Texture2D
@export var text: String

@onready var panel := $%PanelContainer as PanelContainer
@onready var avatar := $%TextureRect as TextureRect
@onready var label := $%Label as Label


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	avatar.texture = texture
	label.text = text
	set_frame_color(Color(0, 0, 0))


func set_frame_color(color: Color) -> void:
	#theme_override_styles/panel
	var box := panel.get_theme_stylebox("panel")
	#panel.add_theme_color_override("font_color", Color(1, 0.5, 0))
	panel.add_theme_color_override("font_color", Color(1, 0.5, 0))

	print(box)
	panel.theme.set_color("border_color", "PanelContainer", color)
