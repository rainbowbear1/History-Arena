extends Node

# Sign-in and result upload for the shared Game Hub. The game never talks to a database
# directly and holds no secrets: in the web build it calls the Hub's JavaScript bridge
# (window.HistoryArenaHub, see docs/hub-integration.md), which the Hub team implements with
# their chosen backend. Without a configured bridge the game runs offline: players continue as
# guests, and finished runs wait in an outbox until they can be uploaded.

signal user_changed(user: Dictionary)

const GAME_ID := "history-arena"
const CLIENT_VERSION := "0.9.0"
const OUTBOX_PATH := "user://outbox.json"
const MAX_OUTBOX := 100
const WebBridgeTransport := preload("res://web_bridge_transport.gd")

var user: Dictionary = {}  # {"uid", "name", "email"} or {"guest": true, "name": ...}
var outbox: Array = []
var outbox_path: String = OUTBOX_PATH
var transport = null  # Object with the methods described in web_bridge_transport.gd, or null.
var flushing: bool = false
var last_error: String = ""


func _ready() -> void:
	load_outbox()
	if OS.has_feature("web") and WebBridgeTransport.bridge_present():
		transport = WebBridgeTransport.new()


func hub_available() -> bool:
	return transport != null and transport.is_configured()


func is_signed_in() -> bool:
	return not user.is_empty()


func is_guest() -> bool:
	return user.get("guest", false)


func display_name() -> String:
	if user.is_empty():
		return ""
	return user.get("name", "") if not is_guest() else "Қонақ (офлайн)"


# Restores an existing Hub session (e.g. the player is already signed in on the Hub site).
func restore_session() -> bool:
	if not hub_available():
		return false
	var restored: Dictionary = transport.current_user()
	if _valid_user(restored):
		_set_user(restored)
		flush_outbox()
		return true
	return false


# Returns "" on success, otherwise a message for the player.
func sign_in_with_google() -> String:
	if not hub_available():
		last_error = "Google арқылы кіру Game Hub қосылғанда жұмыс істейді"
		return last_error
	var result: Dictionary = await transport.sign_in()
	if not _valid_user(result):
		last_error = "Кіру сәтсіз аяқталды: " + str(result.get("error", "белгісіз қате"))
		return last_error
	_set_user(result)
	flush_outbox()
	last_error = ""
	return ""


func continue_as_guest() -> void:
	_set_user({"guest": true, "name": "Қонақ"})


func sign_out() -> void:
	if hub_available() and not is_guest():
		transport.sign_out()
	_set_user({})


# Queues a finished run for the Hub and tries to send it. Never blocks the game.
func submit_attempt(attempt: Dictionary) -> void:
	var payload := attempt.duplicate()
	payload["game_id"] = GAME_ID
	payload["client_version"] = CLIENT_VERSION
	outbox.append(payload)
	if outbox.size() > MAX_OUTBOX:
		outbox = outbox.slice(outbox.size() - MAX_OUTBOX)
	save_outbox()
	flush_outbox()


# Sends queued runs in order; stops at the first failure and keeps the rest for later.
func flush_outbox() -> void:
	if flushing or not hub_available() or not is_signed_in() or is_guest():
		return
	flushing = true
	# Re-check each time: the player may sign out or the Hub may disappear while we wait.
	while not outbox.is_empty() and hub_available() and is_signed_in() and not is_guest():
		var ok: bool = await transport.submit_result(outbox[0])
		if not ok:
			break
		outbox.pop_front()
		save_outbox()
	flushing = false


func load_outbox() -> void:
	outbox = []
	if not FileAccess.file_exists(outbox_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(outbox_path)) == OK and json.data is Array:
		outbox = json.data


func save_outbox() -> void:
	var file := FileAccess.open(outbox_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(outbox))


func _set_user(new_user: Dictionary) -> void:
	user = new_user
	user_changed.emit(user)


static func _valid_user(candidate) -> bool:
	return candidate is Dictionary and candidate.get("uid") is String and not candidate["uid"].is_empty()
