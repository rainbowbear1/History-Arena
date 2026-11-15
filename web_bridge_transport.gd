extends RefCounted

# Talks to window.HistoryArenaHub, the JavaScript bridge in the web page (web/firebase-bridge.js:
# Firebase Authentication + Cloud Firestore). All values cross the bridge as JSON strings. The
# bridge contract is in docs/online.md.
#
# A transport (this class, or a fake one in the tests) provides:
#   is_configured() -> bool
#   wait_user() -> Dictionary               (await; restored session, {} when nobody is signed in)
#   sign_in() -> Dictionary                 (await; user, or {"error": ...})
#   sign_out() -> void
#   submit_result(payload) -> bool          (await; true when the server accepted it)
#   my_progress() -> Dictionary             (await; {"ok", "levels": {"1": {"score", "stars"}}})
#   leaderboard(limit) -> Dictionary        (await; {"ok", "rows": [{"name", "total", "me"}], "me": {"total", "rank"}})

const BRIDGE := "HistoryArenaHub"
const TIMEOUT := 30.0

var hub: JavaScriptObject
var _callbacks: Array = []  # Keep JS callbacks alive until they fire.


# One pending JS promise; settles once, whichever comes first: resolve, reject or timeout.
class Pending:
	extends RefCounted
	signal settled(result: String)
	var done := false

	func finish(result: String) -> void:
		if not done:
			done = true
			settled.emit(result)


# JavaScriptBridge.eval returns JS booleans as numbers, so compare the typeof string instead.
static func bridge_present() -> bool:
	return str(JavaScriptBridge.eval("window.%s ? typeof window.%s : 'missing'" % [BRIDGE, BRIDGE], true)) == "object"


func _init() -> void:
	hub = JavaScriptBridge.get_interface(BRIDGE)


func is_configured() -> bool:
	return hub != null and hub.configured == true


func wait_user() -> Dictionary:
	return _parse_object(await _await_promise(hub.waitForUser()))


func sign_in() -> Dictionary:
	return _parse_object(await _await_promise(hub.signInWithGoogle()))


func sign_out() -> void:
	hub.signOut()


func submit_result(payload: Dictionary) -> bool:
	var text := await _await_promise(hub.submitResult(JSON.stringify(payload)))
	return _parse_object(text).get("ok", false) == true


func my_progress() -> Dictionary:
	return _parse_object(await _await_promise(hub.getMyProgress()))


func leaderboard(limit: int) -> Dictionary:
	return _parse_object(await _await_promise(hub.getLeaderboard(limit)))


# Waits for a JS Promise that resolves to a JSON string; a rejection or timeout becomes {"error": ...}.
func _await_promise(promise) -> String:
	if promise == null:
		return JSON.stringify({"error": "bridge returned no promise"})
	var pending := Pending.new()
	var on_ok := JavaScriptBridge.create_callback(func(args): pending.finish(str(args[0]) if args.size() > 0 and args[0] != null else ""))
	var on_fail := JavaScriptBridge.create_callback(func(args): pending.finish(JSON.stringify({"error": str(args[0]) if args.size() > 0 else "rejected"})))
	_callbacks.append_array([on_ok, on_fail])
	promise.then(on_ok, on_fail)

	var timer: SceneTreeTimer = (Engine.get_main_loop() as SceneTree).create_timer(TIMEOUT)
	timer.timeout.connect(pending.finish.bind(JSON.stringify({"error": "timeout"})))
	var result: String = await pending.settled
	_callbacks.erase(on_ok)
	_callbacks.erase(on_fail)
	return result


static func _parse_object(text) -> Dictionary:
	if not text is String or text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {"error": "invalid bridge response"}
	return json.data
