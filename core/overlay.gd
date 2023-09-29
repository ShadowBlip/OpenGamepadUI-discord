extends OverlayProvider

const Discord := preload("res://plugins/discord/core/discord_client.gd")
const VoiceBanner := preload("res://plugins/discord/core/voice_user_banner.gd")
const VoiceBannerScene := preload("res://plugins/discord/core/voice_user_banner.tscn")

var current_voice_channel := "0"
var current_voice_users := []
var users := {}
var voice_banners: Array[VoiceBanner]
var voice_banners_by_user: Dictionary = {}
var mutex := Mutex.new()

@onready var discord: Discord = get_tree().get_first_node_in_group("discord_client")
@onready var container := $%VoiceContainer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	logger = Log.get_logger("DiscordOverlay", Log.LEVEL.DEBUG)
	if not discord:
		logger.error("Unable to find discord client node!")
		return
	discord.connected.connect(_on_connected)
	discord.socket_closed.connect(_on_disconnected)
	discord.voice_channel_selected.connect(_on_voice_channel_selected)
	discord.voice_state_created.connect(_on_voice_state_created)
	discord.voice_state_updated.connect(_on_voice_state_updated)
	discord.voice_state_deleted.connect(_on_voice_state_deleted)
	discord.speaking_started.connect(_on_speaking_started)
	discord.speaking_stopped.connect(_on_speaking_stopped)
	logger.debug("Overlay ready")


# Update all the voice banners
func update_voice_banners() -> void:
	mutex.lock()
	logger.debug("Updating voice banners")
	# Get all the current users in the voice channel
	var channel := await discord.get_selected_voice_channel()
	var states := []
	if "voice_states" in channel:
		states = channel["voice_states"]
	
	# Create a voice banner for each voice state
	current_voice_users = []
	var user_ids := []
	for state in states:
		if not "user" in state:
			continue
		var user := state["user"] as Dictionary
		if not "id" in user:
			continue
		var id := user["id"] as String
		users[id] = user
		if not id in user_ids:
			current_voice_users.append(user)
			user_ids.append(user["id"])
			logger.debug("Found user: " + user["id"])

	# Remove any user banners that no longer exist
	var existing_banner_ids := []
	var to_remove: Array[VoiceBanner] = []
	for banner in voice_banners:
		var user := banner.get_meta("user") as Dictionary
		if user["id"] in user_ids:
			existing_banner_ids.append(user["id"])
			continue
		logger.debug("Removing banner for user: " + user["id"])
		voice_banners_by_user.erase(user["id"])
		to_remove.append(banner)
	
	for banner in to_remove:
		voice_banners.erase(banner)
		banner.queue_free()
	
	# Create banners for new users
	for user in current_voice_users:
		if user["id"] in existing_banner_ids:
			logger.debug("Banner already exists for user: " + user["id"])
			continue
		var banner := VoiceBannerScene.instantiate()
		banner.set_meta("user", user)
		var avatar := await discord.get_avatar(user["id"], user["avatar"])
		banner.texture = avatar
		banner.text = user["global_name"]
		container.add_child(banner)
		voice_banners.append(banner)
		voice_banners_by_user[user["id"]] = banner
	
	mutex.unlock()


func _on_connected(_user: Dictionary) -> void:
	print("Connected to discord client!")
	# Subscribe to general server events
	discord.sub_server()
	update_voice_banners()


func _on_disconnected() -> void:
	print("Connection to discord client closed")
	pass


func _on_voice_channel_selected(channel: Dictionary) -> void:
	print("Voice channel was selected: ", channel)
	var channel_id := "0"
	if "channel_id" in channel and channel["channel_id"] is String:
		channel_id = channel["channel_id"]
	
	# Unsubscribe from other voice channel events
	if current_voice_channel != "0":
		discord.unsub_voice_channel(current_voice_channel)

	# Set the current voice channel
	current_voice_channel = channel_id
	update_voice_banners()
		
	# If the channel id was null, do nothing
	if channel_id == "0":
		return

	# When a voice channel gets selected, update the current channel and subscribe
	# to any voice events from that channel
	discord.sub_voice_channel(channel_id)


func _on_voice_state_created(_data: Dictionary) -> void:
	update_voice_banners()


func _on_voice_state_updated(_data: Dictionary) -> void:
	update_voice_banners()


func _on_voice_state_deleted(_data: Dictionary) -> void:
	update_voice_banners()


func _on_speaking_started(speaker: Dictionary) -> void:
	var user_id := "0"
	if "user_id" in speaker and speaker["user_id"] is String:
		user_id = speaker["user_id"]

	# Lookup the banner to update
	if not user_id in voice_banners_by_user:
		logger.warn("Unable to find voice banner for user: " + user_id)
		return
	
	var banner := voice_banners_by_user[user_id] as VoiceBanner
	banner.set_talking(true)


func _on_speaking_stopped(speaker: Dictionary) -> void:
	var user_id := "0"
	if "user_id" in speaker and speaker["user_id"] is String:
		user_id = speaker["user_id"]

	# Lookup the banner to update
	if not user_id in voice_banners_by_user:
		logger.warn("Unable to find voice banner for user: " + user_id)
		return
	
	var banner := voice_banners_by_user[user_id] as VoiceBanner
	banner.set_talking(false)


func _get_user(user_id: String) -> Dictionary:
	# Do nothing if no valid user ID was found
	if user_id == "0":
		return {}
	
	# See if we already know the user's username
	if user_id in users:
		return users[user_id]
	
	# Look up the user's username
	var channel := await discord.get_selected_voice_channel()
	if not "voice_states" in channel:
		return {}
	
	for state in channel["voice_states"]:
		if not state is Dictionary:
			continue
		if not "user" in state:
			continue
		var user = state["user"]
		if not "id" in user:
			continue
		if not "global_name" in user:
			continue
		users[user["id"]] = user
		
	if user_id in users:
		return users[user_id]
	return {}
