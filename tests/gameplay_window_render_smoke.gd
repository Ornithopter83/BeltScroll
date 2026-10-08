extends SceneTree

const GATE_SCRIPT := "res://tools/capture_gameplay_window_gate.gd"
const SUCCESS_MARKER := "gameplay_window_render_smoke: all checks passed"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gate_script := load(GATE_SCRIPT)
	if gate_script == null:
		push_error("GWR-003: could not load the gameplay Window render gate.")
		quit(1)
		return
	var gate = gate_script.new()
	var result: Dictionary = await gate.capture(self)
	if not bool(result.get("ok", false)):
		push_error("gameplay_window_render_smoke: gate failed with %s: %s" % [result.get("code", "GWR-000"), result.get("message", "unknown error")])
		quit(1)
		return
	var image := Image.new()
	var image_error := image.load(str(result.get("path", "")))
	if image_error != OK:
		push_error("GWR-012: comparison PNG could not be loaded after capture (error %d)." % image_error)
		quit(1)
		return
	if image.get_size() != Vector2i(1920, 1080):
		push_error("GWR-013: comparison PNG is %s; expected 1920x1080." % image.get_size())
		quit(1)
		return
	print("gameplay_window_render_smoke: verified actual Window Viewport comparison PNG")
	print(SUCCESS_MARKER)
	quit(0)
