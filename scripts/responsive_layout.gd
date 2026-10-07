extends RefCounted
## Reflow fixed-width table bands while preserving card and chip aspect ratios.
static func apply(app: Control, height: float) -> void:
	var extra := maxf(0.0, height - 660.0)
	for surface in [app.home, app.table]:
		if not is_instance_valid(surface): continue
		surface.size = Vector2(1440, height)
		for child in surface.get_children():
			if not child is Control or child == app.flight_layer: continue
			if not child.has_meta("layout_base"):
				child.set_meta("layout_base", Rect2(child.position, child.size))
			var base: Rect2 = child.get_meta("layout_base")
			# Seat widths and x positions belong to the current player count.
			if surface == app.table and base.position.y < 170: continue
			child.position.y = base.position.y
			child.size.y = base.size.y
			if surface == app.home:
				if child is Panel and base.position.y == 108:
					child.size.y += extra
				else:
					child.position.y += extra * 0.5
			else:
				if child is Panel and base.position.y in [185.0, 196.0, 208.0]:
					child.size.y += extra
				elif child == app.phase_label:
					pass # Keep the stage caption at the table's top-left edge.
				elif base.position.y >= 408:
					child.position.y += extra
				elif base.position.y >= 200:
					child.position.y += extra * 0.5
	app.flight_layer.size = Vector2(1440, height)
	app.toast_label.position.y = height - 22
	if is_instance_valid(app.modal):
		app.modal.size = Vector2(1440, height)
		if app.modal.has_method("set_available_height"):
			app.modal.set_available_height(height)
		else:
			for child in app.modal.get_children():
				if child is ColorRect: child.size = Vector2(1440, height)
				elif child is Panel: child.position.y = (height - child.size.y) * 0.5
