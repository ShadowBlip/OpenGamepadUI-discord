extends Node

## Discord client
##
## Based off of trigg's work here: 
## https://github.com/trigg/Discover/blob/master/discover_overlay/discord_connector.py

## Emitted when connected and authenticated
signal connected(user: Dictionary)
## Emitted when a websocket connection is established to the Discord client
signal socket_connected()
## Emitted when the websocket connection is closed
signal socket_closed()
## Emitted whenever a WebSocket message is received from Discord
signal message_received(msg: Message)

# Subscribed event signals
signal message_created(msg: Dictionary)
signal message_updated(msg: Dictionary)
signal message_deleted(msg: Dictionary)
signal voice_state_updated(state: Dictionary)
signal voice_state_created(state: Dictionary)
signal voice_state_deleted(state: Dictionary)
signal speaking_started(data: Dictionary)
signal speaking_stopped(data: Dictionary)
signal voice_channel_selected(channel: Dictionary)
signal voice_connection_status_changed(status: Dictionary)
signal channel_created(channel: Dictionary)
signal notification_created(notify: Dictionary)

const CONNECT_URL := "ws://127.0.0.1:6463/?v=1&client_id={0}"
const OAUTH_TOKEN := "207646673902501888"
const WS_ORIGIN := "https://streamkit.discord.com"

## Different types of Discord channels
enum CHANNEL_TYPE {
	TEXT = 0,
	VOICE = 2,
	CATEGORY = 4,
	STAGE = 13,
	FORUM = 15,
}

var streamkit_api := HTTPAPIClient.new()
var websocket := WebSocketPeer.new()
var access_token := "none"
var authed := false
var ws_connected := false
var user := {}
var logger := Log.get_logger("DiscordClient", Log.LEVEL.DEBUG)


func _ready() -> void:
	# Set the node group so other scenes can use the client.
	add_to_group("discord_client")
	
	# Configure WS headers
	var origin_header := "Origin: {0}".format([WS_ORIGIN])
	logger.debug("Setting header: " + origin_header)
	websocket.handshake_headers = [origin_header]
	
	# Configure and add the Streamkit HTTP API Client
	streamkit_api.base_url = WS_ORIGIN
	add_child(streamkit_api)
	
	# Connect to signals
	message_received.connect(_on_message)
	connected.connect(_on_connected)
	socket_closed.connect(_on_closed)


## Tries to open the connection to the Discord client
func open() -> int:
	var url := CONNECT_URL.format([OAUTH_TOKEN])
	logger.info("Connecting to discord websocket at: " + url)
	var err := websocket.connect_to_url(CONNECT_URL.format([OAUTH_TOKEN]))
	if err != OK:
		logger.warn("Failed to connect to websocket: " + str(err))
		return err
	
	set_process(true)
	return OK


# Close the websocket connection
func close() -> void:
	websocket.close()


## Send a Discord command request and block until a response is returned
func send_req(req: Request) -> Variant:
	send_req_nonblock(req)
	var msg := await message_received as Message
	while not msg.is_response_for(req):
		msg = await message_received
	
	return msg.data


## Send the given Discord command request without waiting for a response.
func send_req_nonblock(req: Request) -> void:
	var args_str := str(req.args) if req.args.size() > 0 else ""
	logger.debug("Sending command: " + req.cmd + " " + args_str)
	var cmd := {
		"cmd": req.cmd,
		"nonce": req.nonce,
	}
	if req.args.size() > 0:
		cmd["args"] = req.args
	if req.evt != "":
		cmd["evt"] = req.evt
	if websocket.send_text(JSON.stringify(cmd)) != OK:
		logger.warn("Unable to send request: " + req.cmd)


## Request authentication token
func req_auth() -> void:
	logger.debug("Requesting authentication token")
	var req := Request.new("AUTHENTICATE", {"access_token": access_token})
	send_req_nonblock(req)


## Request info on one guild
func req_guild(guild_id: String) -> void:
	logger.debug("Requesting guild: " + guild_id)
	var req := Request.new("GET_GUILD", {"guild_id": guild_id})
	send_req_nonblock(req)


## Request all guilds information for logged in user
func req_guilds() -> void:
	logger.debug("Requesting guilds")
	var req := Request.new("GET_GUILDS")
	send_req_nonblock(req)


## Get all guilds for the logged in user
func get_guilds() -> Array[Dictionary]:
	var guilds: Array[Dictionary]
	var req := Request.new("GET_GUILDS")
	var res = await send_req(req)
	if not "guilds" in res:
		return guilds
	guilds.assign(res["guilds"])
	
	return guilds


## Request all channels information for given guild.
func req_channels(guild_id: String) -> void:
	logger.debug("Requesting channels")
	var req := Request.new("GET_CHANNELS", {"guild_id": guild_id}, guild_id)
	send_req_nonblock(req)


## Get all channel information for a given guild.
func get_channels(guild_id: String) -> Array[Dictionary]:
	var channels: Array[Dictionary]
	var req := Request.new("GET_CHANNELS", {"guild_id": guild_id}, guild_id)
	var res = await send_req(req)
	if not "channels" in res:
		return channels
	channels.assign(res["channels"])
	
	return channels


## Request information about a specific channel
func req_channel_details(channel_id: String, nonce: String = "") -> void:
	logger.debug("Requesting channel details: " + channel_id)
	if nonce == "":
		nonce = channel_id
	var req := Request.new("GET_CHANNEL", {"channel_id": channel_id}, nonce)
	send_req_nonblock(req)


## Returns details about the currently selected voice channel
func get_selected_voice_channel() -> Dictionary:
	var req := Request.new("GET_SELECTED_VOICE_CHANNEL", {}, "test")
	var res = await send_req(req)
	if not res is Dictionary:
		return {}
	if not "voice_states" in res:
		return {}
	
	return res as Dictionary


## Returns the avatar texture for the given user.
## https://cdn.discordapp.com/avatars/{user.id}/{user.avatar}.png
func get_avatar(user_id: String, avatar_id: String) -> Texture2D:
	var image_fetcher := HTTPImageFetcher.new()
	add_child(image_fetcher)
	
	var url := "https://cdn.discordapp.com/avatars/{0}/{1}.png".format([user_id, avatar_id])
	var image := await image_fetcher.fetch(url)
	image_fetcher.queue_free()

	return image


## Subscribe to event helper function
func sub_raw(event: String, args: Dictionary, nonce: String) -> void:
	var req := Request.new("SUBSCRIBE", args, nonce)
	req.evt = event
	send_req_nonblock(req)


## Unsubscribe to event helper function
func unsub_raw(event: String, args: Dictionary, nonce: String) -> void:
	var req := Request.new("UNSUBSCRIBE", args, nonce)
	req.evt = event
	send_req_nonblock(req)


## Subscribe to helpful events that report connectivity issues &
## when the user has intentionally changed channel
##
## Unfortunatly no event has been found to alert to being forcibly moved
## or that reports the users current location
func sub_server() -> void:
	sub_raw("VOICE_CHANNEL_SELECT", {}, "VOICE_CHANNEL_SELECT")
	sub_raw("VOICE_CONNECTION_STATUS", {}, "VOICE_CONNECTION_STATUS")
	sub_raw("GUILD_CREATE", {}, "GUILD_CREATE")
	sub_raw("CHANNEL_CREATE", {}, "CHANNEL_CREATE")
	sub_raw("NOTIFICATION_CREATE", {}, "NOTIFICATION_CREATE")


## Subscribe to event on channel
func sub_channel(event: String, channel_id: String) -> void:
	sub_raw(event, {"channel_id": channel_id}, channel_id)


## Unsubscribe to event on channel
func unsub_channel(event: String, channel_id: String) -> void:
	unsub_raw(event, {"channel_id": channel_id}, channel_id)


## Subscribe to text-based events.
func sub_text_channel(channel_id: String) -> void:
	sub_channel("MESSAGE_CREATE", channel_id)
	sub_channel("MESSAGE_UPDATE", channel_id)
	sub_channel("MESSAGE_DELETE", channel_id)

#{"cmd":"DISPATCH","data":{"channel_id":"953357921327149077","message":{"id":"1133148287751434261","content":"Hmm","content_parsed":[{"type":"text","content":"Hmm","originalMatch":{"0":"Hmm","index":0}}],"nick":"ShadowApex","author_color":"#1f8b4c","timestamp":"2023-07-24T21:26:44.677000+00:00","tts":false,"mentions":[],"mention_roles":[],"embeds":[],"attachments":[],"author":{"id":"223691993639813120","username":"shadowapex","discriminator":"0","avatar":"fd588356362a8434f45c07f3d1003e8c","premium_type":0},"pinned":false,"type":0}},"evt":"MESSAGE_CREATE","nonce":null}


## Unsubscribe to text-based events.
func unsub_text_channel(channel_id: String) -> void:
	unsub_channel("MESSAGE_CREATE", channel_id)
	unsub_channel("MESSAGE_UPDATE", channel_id)
	unsub_channel("MESSAGE_DELETE", channel_id)


## Subscribe to voice-based events.
func sub_voice_channel(channel_id: String) -> void:
	sub_channel("VOICE_STATE_CREATE", channel_id)
	sub_channel("VOICE_STATE_UPDATE", channel_id)
	sub_channel("VOICE_STATE_DELETE", channel_id)
	sub_channel("SPEAKING_START", channel_id)
	sub_channel("SPEAKING_STOP", channel_id)


## Unsubscribe to voice-based events.
func unsub_voice_channel(channel_id: String) -> void:
	unsub_channel("VOICE_STATE_CREATE", channel_id)
	unsub_channel("VOICE_STATE_UPDATE", channel_id)
	unsub_channel("VOICE_STATE_DELETE", channel_id)
	unsub_channel("SPEAKING_START", channel_id)
	unsub_channel("SPEAKING_STOP", channel_id)


## Request a recent version of voice settings
func get_voice_settings() -> void:
	var req := Request.new("GET_VOICE_SETTINGS")
	send_req_nonblock(req)


## Set mute voice setting
func set_mute(muted: bool) -> void:
	var req := Request.new("SET_VOICE_SETTINGS", {"mute": muted})
	send_req_nonblock(req)


## Set deaf voice setting
func set_deaf(deaf: bool) -> void:
	var req := Request.new("SET_VOICE_SETTINGS", {"deaf": deaf})
	send_req_nonblock(req)


## Switch to another voice room
func change_voice_room(channel_id: String) -> void:
	var req := Request.new("SELECT_VOICE_CHANNEL", {"channel_id": channel_id, "force": true})
	send_req_nonblock(req)


## Switch to another text room
func change_text_room(channel_id: String) -> void:
	var req := Request.new("SELECT_TEXT_CHANNEL", {"channel_id": channel_id})
	send_req_nonblock(req)


## First stage of getting an access token. Request authorization from Discord client
func get_access_token_stage1() -> void:
	logger.debug("Requesting first stage authorization")
	var req := Request.new("AUTHORIZE")
	req.args = {
		"client_id": OAUTH_TOKEN,
		"scopes": ["rpc", "messages.read", "rpc.notifications.read"],
		"prompt": "none",
	}
	send_req_nonblock(req)


## Second stage of getting an access token. Give auth code to streamkit
func get_access_token_stage2(code: String) -> void:
	logger.debug("Requesting second stage authorization")
	var path := "/overlay/token"
	var caching := Cache.FLAGS.NONE
	var headers := []
	var method := HTTPClient.METHOD_POST
	var data := JSON.stringify({"code": code})
	
	var response := await streamkit_api.request(path, caching, headers, method, data) as HTTPAPIClient.Response
	if response.code != 200:
		logger.warn("Received non-200 response: " + str(response.code))
		return
	
	var parsed = response.get_json()
	if not parsed is Dictionary:
		logger.warn("Invalid auth response: " + str(parsed))
		return
	if not "access_token" in parsed:
		logger.warn("No access token in JSON response")
		logger.warn(parsed)
		_on_closed()
		return
	
	access_token = parsed["access_token"]
	req_auth()


# Polls the socket every frame for data
func _process(delta):
	websocket.poll()
	var state = websocket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not ws_connected:
			ws_connected = true
			socket_connected.emit()
		while websocket.get_available_packet_count():
			_process_response(websocket.get_packet())
		return
	if state == WebSocketPeer.STATE_CLOSING:
		# Keep polling to achieve proper close.
		return
	if state == WebSocketPeer.STATE_CLOSED:
		var code = websocket.get_close_code()
		var reason = websocket.get_close_reason()
		ws_connected = false
		socket_closed.emit()
		logger.debug("WebSocket closed with code: %d, reason %s. Clean: %s" % [code, reason, code != -1])
		set_process(false) # Stop processing.


# Process responses and parse them
func _process_response(data: PackedByteArray) -> void:
	var response_str := data.get_string_from_utf8()
	logger.debug("Got response: " + response_str)
	
	var parsed = JSON.parse_string(response_str)
	if not parsed is Dictionary:
		logger.debug("Failed to parse response JSON")
		return

	var response := parsed as Dictionary
	if not "cmd" in response:
		logger.warn("No 'cmd' found in response")
		return
	var msg := Message.new()
	msg.cmd = response["cmd"]
	if "evt" in response and response["evt"] is String:
		msg.evt = response["evt"]
	if "data" in response:
		msg.data = response["data"]
	if "nonce" in response and response["nonce"] is String:
		msg.nonce = response["nonce"]
	
	message_received.emit(msg)


# Process a received message
func _on_message(msg: Message) -> void:
	var cmd := msg.cmd
	if cmd == "AUTHORIZE":
		_on_message_authorize(msg)
	elif cmd == "DISPATCH":
		_on_message_dispatch(msg)
	elif cmd == "AUTHENTICATE":
		_on_message_authenticate(msg)
	elif cmd == "GET_GUILDS":
		pass
	elif cmd == "GET_GUILD":
		pass
	elif cmd == "GET_CHANNEL":
		pass
	elif cmd == "GET_CHANNELS":
		pass
	elif cmd == "SUBSCRIBE":
		pass
	elif cmd == "UNSUBSCRIBE":
		pass
	elif cmd == "GET_SELECTED_VOICE_CHANNEL":
		pass
	elif cmd == "SELECT_VOICE_CHANNEL":
		pass
	elif cmd == "SET_VOICE_SETTINGS":
		pass
	elif cmd == "GET_VOICE_SETTINGS":
		pass
	else:
		logger.warn("Unknown command: " + cmd)


func _on_message_authorize(msg: Message) -> void:
	get_access_token_stage2(msg.data["code"])


# Process 'DISPATCH' messages
func _on_message_dispatch(msg: Message) -> void:
	var event := msg.evt
	if event == "READY":
		req_auth()
	elif event == "VOICE_STATE_UPDATE":
		voice_state_updated.emit(msg.data)
	elif event == "VOICE_STATE_CREATE":
		voice_state_created.emit(msg.data)
	elif event == "VOICE_STATE_DELETE":
		voice_state_deleted.emit(msg.data)
	elif event == "SPEAKING_START":
		speaking_started.emit(msg.data)
	elif event == "SPEAKING_STOP":
		speaking_stopped.emit(msg.data)
	elif event == "VOICE_CHANNEL_SELECT":
		voice_channel_selected.emit(msg.data)
	elif event == "VOICE_CONNECTION_STATUS":
		voice_connection_status_changed.emit(msg.data)
	elif event == "MESSAGE_CREATE":
		message_created.emit(msg.data)
	elif event == "MESSAGE_UPDATE":
		message_updated.emit(msg.data)
	elif event == "MESSAGE_DELETE":
		message_deleted.emit(msg.data)
	elif event == "CHANNEL_CREATE":
		channel_created.emit(msg.data)
	elif event == "NOTIFICATION_CREATE":
		notification_created.emit(msg.data)
	else:
		logger.warn("Unknown event type: " + event)


# Process 'AUTHENTICATE' messages
func _on_message_authenticate(msg: Message) -> void:
	var event := msg.evt
	if event == "ERROR":
		get_access_token_stage1()
		return

	user = msg.data["user"]
	logger.info("ID is " + user["id"])
	logger.info("Logged in as " + user["username"])
	authed = true

	connected.emit(user)


# Called when connected and authenticated
func _on_connected(_user: Dictionary) -> void:
	pass


# Called when the connection fails
func _on_closed() -> void:
	logger.warn("Connection closed")
	authed = false


## Structure for holding parsed Discord message objects
class Message:
	var cmd: String
	var evt: String
	var data: Variant
	var nonce: String

	# Returns true if the given message is a response for this request
	func is_response_for(req: Request) -> bool:
		return cmd == req.cmd and nonce == req.nonce

	func _to_string() -> String:
		return "Message<{0},{1},{2}>".format([cmd, evt, nonce])


## Structure for sending a websocket request to Discord
class Request:
	var cmd: String
	var args: Dictionary
	var evt: String
	var nonce: String = "deadbeef"

	func _init(command: String, arguments: Dictionary = {}, id: String = "deadbeef") -> void:
		cmd = command
		args = arguments
		nonce = id

	func _to_string() -> String:
		return "Request<{0},{1},{2},{3}>".format([cmd, str(args), evt, nonce])
