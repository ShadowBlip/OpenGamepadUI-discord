extends Plugin

const Discord := preload("res://plugins/discord/core/discord_client.gd")

var discord: Discord = Discord.new()
var overlay_scene := load("res://plugins/discord/core/overlay.tscn") as PackedScene

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	logger = Log.get_logger("Discord", Log.LEVEL.DEBUG)
	logger.info("Discord plugin loaded")
	
	# Add the overlay scene to main
	var main := get_tree().get_first_node_in_group("main")
	if not main:
		logger.error("No node in the 'main' node group to add overlay to")
		return
	
	logger.debug("Adding discord client node")
	add_child(discord)
	logger.debug("Opening connection to discord client")
	discord.open.call_deferred()

	# Add the overlay scene to the main scene
	logger.debug("Adding overlay to interface " + main.name)
	var overlay := overlay_scene.instantiate()
	main.add_child.call_deferred(overlay)
