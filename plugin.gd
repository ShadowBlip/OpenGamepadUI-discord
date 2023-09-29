extends Plugin

const Discord := preload("res://plugins/discord/core/discord_client.gd")

var discord: Discord = Discord.new()
var overlay_scene := load("res://plugins/discord/core/overlay.tscn") as PackedScene
var overlay := overlay_scene.instantiate()


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	logger = Log.get_logger("Discord", Log.LEVEL.DEBUG)
	logger.info("Discord plugin loaded")
	
	logger.debug("Adding discord client node")
	add_child(discord)
	logger.debug("Opening connection to discord client")
	discord.open.call_deferred()

	# Add the overlay scene to the main scene
	logger.debug("Adding overlay to interface")
	add_overlay(overlay)


## Called when the plugin is unloaded
func unload() -> void:
	overlay.queue_free()
	discord.queue_free()
