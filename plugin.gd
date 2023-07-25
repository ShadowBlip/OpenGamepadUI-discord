extends Plugin

const Discord := preload("res://plugins/discord/core/discord_client.gd")

var discord: Discord = Discord.new()


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	logger = Log.get_logger("Discord", Log.LEVEL.DEBUG)
	logger.info("Discord plugin loaded")
	add_child(discord)
	discord.open.call_deferred()

