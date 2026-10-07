extends SceneTree
const Main = preload("res://scenes/main.tscn")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var app = Main.instantiate()
	root.add_child(app)
	await process_frame
	app.music.set_paused(false)
	await create_timer(0.15).timeout
	app._cancel_home_entrance()
	app.home_chip_display.flourish(4)
	app._exit_game()
	app._exit_game() # Repeated confirmation does not queue another exit.
	if not app._exit_pending or app.music._player.playing or app.music._player.stream != null or not app.home_chip_display._animation_kind.is_empty():
		push_error("Exit must stop the streaming player before quitting")
		quit(1)
		return
	print("EXIT_PROCESS_SUMMARY checks=4 failures=0")
