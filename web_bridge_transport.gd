extends RefCounted

# Talks to window.HistoryArenaHub, the JavaScript bridge the Game Hub provides in the web page.
# All values cross the bridge as JSON strings. The bridge contract is in docs/hub-integration.md.
#
# A transport (this class, or a fake one in the tests) provides:
#   is_configured() -> bool
#   current_user() -> Dictionary            ({} when nobody is signed in)
#   sign_in() -> Dictionary                 (await; user, or {"error": ...})
#   sign_out() -> void
#   submit_result(payload) -> bool          (await; true when the Hub accepted it)

signal _settled(result: String)

const BRIDGE := "HistoryArenaHub"
const TIMEOUT := 30.0

var hub: JavaScriptObject
var _callbacks: Array = []  # Keep JS callbacks alive until they fire.


# JavaScriptBridge.eval returns JS booleans as numbers, so compare the typeof string instead.
static func bridge_present() -> bool:
	return str(JavaScriptBridge.eval("window.%s ? typeof window.%s : 'missing'" % [BRIDGE, BRIDGE], true)) == "object"


func _init() -> void:
	hub = JavaScriptBridge.get_interface(BRIDGE)


func is_configured() -> bool:
	return hub != null and hub.configured == true


func current_user() -> Dictionary:
	var text = hub.getCurrentUser()
	return _parse_object(text)


func sign_in() -> Dictionary:
	var text := await _await_promise(hub.signInWithGoogle())
	return _parse_object(text)


func sign_out() -> void:
	hub.signOut()


func submit_result(payload: Dictionary) -> bool:
	var text := await _await_promise(hub.submitResult(JSON.stringify(payload)))
	return _parse_object(text).get("ok", false) == true


# Waits for a JS Promise that resolves to a JSON string; a rejection or timeout becomes {"error": ...}.
func _await_promise(promise) -> String:
	if promise == null:
		return JSON.stringify({"error": "bridge returned no promise"})
	var on_ok := JavaScriptBridge.create_callback(func(args): _settled.emit(str(args[0]) if args.size() > 0 else ""))
	var on_fail := JavaScriptBridge.create_callback(func(args): _settled.emit(JSON.stringify({"error": str(args[0]) if args.size() > 0 else "rejected"})))
	_callbacks.append_array([on_ok, on_fail])
	promise.then(on_ok, on_fail)

	var timer: SceneTreeTimer = (Engine.get_main_loop() as SceneTree).create_timer(TIMEOUT)
	timer.timeout.connect(func(): _settled.emit(JSON.stringify({"error": "timeout"})))
	var result: String = await _settled
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
