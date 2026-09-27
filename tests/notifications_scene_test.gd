extends "res://tests/a3_scene_test.gd"
var notices: Dictionary
var profile: Dictionary
var replay_count := 0
var report_id := ""
var page_number := 0
func _ready() -> void:
	await settle()
	app.api.get_node("Poll").stop()
	var screen = app.notifications_screen
	notices = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/api/b5/recorded/fixtures/improved/notifications.json")).response
	profile = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/api/b5/recorded/fixtures/improved/profile.json")).response.profile
	screen.reduced_motion = true
	screen.replay_requested.disconnect(app._on_back_to_start)
	screen.report_requested.disconnect(app._open_archived_report)
	screen.list_requested.disconnect(app._load_notifications)
	screen.replay_requested.connect(func(): replay_count += 1)
	screen.report_requested.connect(func(id): report_id = id)
	screen.list_requested.connect(func(page): page_number = page)
	app.screens.current_tab = 7
	screen.present_profile(profile)
	screen.present(notices)
	check(screen.entries.size() == 3,"Confirmed event, practice, and earned achievement")
	check(screen.get_node("%Secondary").disabled,"Future carriage cannot start a trip")
	check(screen.get_node("%DetailTitle").text.contains("КОМФОРТ"),"Concept title for unlocked carriage")
	screen.get_node("%Primary").pressed.emit()
	check(replay_count == 1,"Future carriage action returns to training")
	screen._select(2,true)
	screen.get_node("%Primary").pressed.emit()
	check(report_id == screen.entries[2].trip_id,"Award opens the exact saved report")
	screen._select(1,true)
	var retained: String = screen.selected_id
	screen.present(notices)
	check(screen.selected_id == retained,"Refresh preserves selected event")
	screen.reduced_motion = false
	for i in 15:
		screen._select(i%3)
		await get_tree().create_timer(0.012).timeout
	await get_tree().create_timer(0.4).timeout
	check(screen.selected_index == 2 and screen.get_node("%DetailTitle").text == "БЕЗОПАСНЫЙ РЕЙС","Rapid selections settle on latest event")
	check(is_equal_approx(screen.detail.modulate.a,1.0),"Interrupted transition restores opacity")
	Engine.time_scale = 0
	screen._select(0)
	await get_tree().create_timer(0.4,true,false,true).timeout
	check(screen.get_node("%DetailTitle").text.contains("КОМФОРТ") and is_equal_approx(screen.detail.modulate.a,1.0),"UI transitions continue when simulation time is frozen")
	Engine.time_scale = 1
	screen.reduced_motion = true
	screen._select(1)
	check(screen.get_node("%DetailTitle").text == "ПРОВЕРКА УСЛОВИЙ" and is_equal_approx(screen.detail.modulate.a,1.0),"Reduced motion switches immediately")
	screen.loading()
	check(screen.cards.is_empty() and screen.get_node("%Primary").disabled,"Loading clears stale actions")
	screen.failed("Связь потеряна")
	check(screen.cards.is_empty() and screen.get_node("%Primary").text.contains("ПОВТОРИТЬ"),"Error provides retry, no fake unlock")
	screen.get_node("%Primary").pressed.emit()
	check(page_number == 1,"Retry requests the same page")
	screen.profile = {}
	screen.present({"notifications":[],"page":1,"total":0})
	check(screen.cards.is_empty() and screen.get_node("%DetailTitle").text.contains("НЕТ"),"Empty journal is explicit")
	var pending := profile.duplicate(true)
	for award in pending.achievements: award.earned = false
	screen.present_profile(pending)
	check(screen.entries.size() == 1 and screen.entries[0].kind == "practice","No unearned achievement fabricated")
	var paged := notices.duplicate(true)
	paged.total = 7
	paged.page = 2
	paged.notifications = []
	for i in 3:
		paged.notifications.append({"id":"other-"+str(i),"title":"Событие "+str(i),"message":"Подробное пояснение события. ".repeat(30),"created_at":"2026-09-27T10:00:00Z","carriage_id":"","content_status":""})
	screen.present(paged)
	check(screen.entries.size() == 3,"Remote page preserves every event without context duplicates")
	screen.get_node("%Next").pressed.emit()
	check(page_number == 3,"Next page requests actual remote page")
	screen.get_node("%Previous").pressed.emit()
	check(page_number == 1,"Previous page requests actual remote page")
	check(screen.get_node("%DetailBody").text == paged.notifications[0].message,"Full server body preserved")
	screen.present_profile(profile)
	screen.present(notices)
	screen.reduced_motion = true
	for dimensions in [Vector2i(1280,720),Vector2i(1024,768),Vector2i(360,640)]:
		get_window().size = dimensions
		screen._select(0,true)
		await settle()
		layout(screen,dimensions.x)
		check(screen.get_node("%DetailPanel").size.x > 400,"Details remain readable after resize")
		if dimensions.x >= 900:
			check(screen.list_box.size.y <= screen.list_scroll.size.y,"Three cards fully fit desktop")
		for i in 3:
			screen._select(i,true)
			await settle()
			check(screen.get_node("%Primary").get_global_rect().end.x <= dimensions.x,"Action remains inside viewport")
		if "--visual" in OS.get_cmdline_user_args():
			screen._select(0,true)
			screen.scroller.scroll_vertical = 0
			await settle()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_webp("res://.gdskills/notifications-%s.webp" % dimensions.x)
			if dimensions.x == 360:
				screen.scroller.scroll_vertical = int(800*screen.stage.scale.y)
				await settle()
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_webp("res://.gdskills/notifications-mobile-detail.webp")
	print("NOTIFICATIONS checks=%s failures=%s" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
