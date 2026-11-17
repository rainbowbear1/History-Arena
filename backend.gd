extends Node

# Google sign-in, saved results and the online leaderboard. The game never talks to a database
# directly and holds no secrets: in the web build it calls the JavaScript bridge
# (window.HistoryArenaHub, web/firebase-bridge.js, contract in docs/online.md), which uses Firebase
# Authentication and Cloud Firestore. Without a configured bridge the game runs offline as a guest.
#
# Finished runs of a signed-in player wait in an outbox (tagged with the player's uid) until the
# server accepts them, so a lost connection loses nothing. Guest runs stay on this device only.

signal user_changed(user: Dictionary)

const GAME_ID := "history-arena"
const CLIENT_VERSION := "1.0.0"
const OUTBOX_PATH := "user://outbox.json"
const MAX_OUTBOX := 100
const OFFLINE_MESSAGE := "Онлайн режим бапталмаған: Google арқылы кіру жұмыс істемейді"
const WebBridgeTransport := preload("res://web_bridge_transport.gd")
const POPUP_CLOSED := "кіру терезесі жабылды"  # Bridge message when the player closes the Google window.
const LOAD_ERROR := "Firebase жүктелмеді: "

var user: Dictionary = {}  # {"uid", "name"} or {"guest": true, "name": ...}
var outbox: Array = []
var outbox_path: String = OUTBOX_PATH
var transport = null  # Object with the methods described in web_bridge_transport.gd, or null.
var flushing: bool = false
var upload_gap: float = 6.0  # The security rules accept one result per player every 5 seconds.
var last_error: String = ""
var last_upload_ok: bool = false


func _ready() -> void:
	load_outbox()
	if OS.has_feature("web") and WebBridgeTransport.bridge_present():
		transport = WebBridgeTransport.new()


func online_available() -> bool:
	return transport != null and transport.is_configured()


func is_signed_in() -> bool:
	return not user.is_empty()


func is_guest() -> bool:
	return user.get("guest", false)


func is_online_player() -> bool:
	return is_signed_in() and not is_guest() and online_available()


func display_name() -> String:
	if user.is_empty():
		return ""
	return user.get("name", "") if not is_guest() else tr("Қонақ (офлайн)")


# Restores a saved Google session (Firebase keeps it across page reloads).
func restore_session() -> bool:
	if not online_available():
		return false
	var restored: Dictionary = await transport.wait_user()
	if not _valid_user(restored):
		return false
	_set_user(restored)
	await _after_sign_in()
	return true


# Returns "" on success, otherwise a message for the player.
func sign_in_with_google() -> String:
	if not online_available():
		last_error = tr(OFFLINE_MESSAGE)
		return last_error
	var result: Dictionary = await transport.sign_in()
	if not _valid_user(result):
		var reason := str(result.get("error", "белгісіз қате"))
		# Closing the Google window is a choice, not a failure.
		if reason == POPUP_CLOSED:
			last_error = tr("Кіру тоқтатылды. Қайта көріңіз немесе қонақ ретінде ойнаңыз.")
		else:
			last_error = tr("Кіру сәтсіз аяқталды: ") + bridge_message(reason)
		return last_error
	_set_user(result)
	await _after_sign_in()
	last_error = ""
	return ""


func continue_as_guest() -> void:
	_set_user({"guest": true, "name": "Қонақ"})


func sign_out() -> void:
	if online_available() and not is_guest():
		transport.sign_out()
	_set_user({})


# Records a finished run for the online leaderboard and tries to send it. Never blocks the game.
func submit_attempt(attempt: Dictionary) -> void:
	if not is_signed_in() or is_guest():
		return
	var payload := attempt.duplicate()
	payload["game_id"] = GAME_ID
	payload["client_version"] = CLIENT_VERSION
	payload["owner"] = user["uid"]  # Local only: which account the run belongs to. Not sent.
	outbox.append(payload)
	if outbox.size() > MAX_OUTBOX:
		outbox = outbox.slice(outbox.size() - MAX_OUTBOX)
	save_outbox()
	flush_outbox()


# Sends the current player's queued runs in order; stops at the first failure and keeps the rest.
# Runs queued by other accounts on this device wait until that account signs in again.
func flush_outbox() -> void:
	if flushing or not is_online_player():
		return
	flushing = true
	var uid: String = user["uid"]
	var sent := 0
	# Re-check each time: the player may sign out while we wait.
	while is_online_player() and user.get("uid") == uid:
		var index: int = outbox.find_custom(func(p): return p is Dictionary and p.get("owner") == uid)
		if index < 0:
			break
		var entry: Dictionary = outbox[index]
		if sent > 0:
			await get_tree().create_timer(upload_gap).timeout
		var payload := entry.duplicate()
		payload.erase("owner")
		var ok: bool = await transport.submit_result(payload)
		last_upload_ok = ok
		if not ok:
			break
		outbox.erase(entry)
		save_outbox()
		sent += 1
	flushing = false


func pending_uploads() -> int:
	var uid = user.get("uid", "")
	return outbox.filter(func(p): return p is Dictionary and p.get("owner") == uid).size()


# {"ok": true, "rows": [{"name", "total", "me"}], "me": {"total", "rank"}} or {"error": ...}
func fetch_leaderboard(limit: int = 20) -> Dictionary:
	if not is_online_player():
		return {"error": tr("Рейтингті көру үшін Google арқылы кіріңіз")}
	var result: Dictionary = await transport.leaderboard(limit)
	if result.get("ok") != true:
		return {"error": tr("Рейтинг жүктелмеді: ") + bridge_message(str(result.get("error", "белгісіз қате")))}
	return result


# The bridge reports problems in Kazakh (web/firebase-bridge.js); they are keys in locale/en.json.
# A Firebase loading error carries the browser's own detail after the prefix.
func bridge_message(text: String) -> String:
	if text.begins_with(LOAD_ERROR):
		return tr(LOAD_ERROR) + text.trim_prefix(LOAD_ERROR)
	return tr(text)


# Brings best scores saved online (e.g. on another computer) into this device's progress.
func sync_progress() -> void:
	if not is_online_player():
		return
	var remote: Dictionary = await transport.my_progress()
	if remote.get("ok") == true and remote.get("levels") is Dictionary:
		ProgressStore.merge_remote(remote["levels"])


func _after_sign_in() -> void:
	await sync_progress()
	flush_outbox()


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
	# Each Google account has its own progress on this device; guests share the default file.
	ProgressStore.use_profile("" if is_guest() else str(user.get("uid", "")))
	user_changed.emit(user)


static func _valid_user(candidate) -> bool:
	return candidate is Dictionary and candidate.get("uid") is String and not candidate["uid"].is_empty()
