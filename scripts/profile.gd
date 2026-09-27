extends "res://scripts/progress_screen.gd"
signal report_requested(trip_id: String)
const Data = preload("res://scripts/progress_data.gd")
const Text = preload("res://scripts/server_text.gd")
var profile: Dictionary = {}

func _ready() -> void:
	resized.connect(_adapt_layout)
	_adapt_layout()
	%Body.visible = false

func _adapt_layout() -> void:
	%Skills.columns = 3 if size.x >= 950 else 1
	%Achievements.columns = %Skills.columns

func loading() -> void:
	%Body.visible = false
	set_status("Загружаем сохранённый профиль…", false, true)

func failed(message: String) -> void:
	%Body.visible = false
	set_status(message, true)

func present(value: Dictionary) -> void:
	profile = value
	%Body.visible = true
	%Identity.text = "%s\nОчки: %s · Завершено рейсов: %s" % [value.display_name, Text.metric(value.total_points), Text.metric(value.completed_trips)]
	var slots := {"communication": %Communication, "safety": %Safety, "prioritization": %Prioritization}
	for item in value.competencies:
		slots[item.id].present({"title": item.name, "detail": "%s очков" % Text.metric(item.points), "footnote": "По лучшим результатам сохранённых рейсов"})
	var achievements := {"first_trip": %FirstTrip, "safety_resolved": %SafeTrip, "checked_before_promise": %CheckedConditions}
	for item in value.achievements:
		achievements[item.id].present({"title": item.name + (" · Получено" if item.earned else " · Пока не получено"), "detail": "Достижение подтверждено сервером" if item.earned else "Выполните условия в тренировке", "footnote": str(item.get("earned_at", "")) if item.earned else "Условие проверяет сервер"})
	%Recommendation.text = "Следующая тренировка\n" + "Повторите рейс, чтобы улучшить личные рекорды. Рекомендации по решениям доступны в отчётах."
	var records: Array = []
	for id in value.report_ids:
		records.append({"title": "Сохранённый рейс", "detail": "Оценки и рекомендации в отчёте", "footnote": "Рейс: " + id, "target": id, "action": "Открыть сохранённый отчёт"})
	for item in value.best_results:
		records.append({"title": "Рекорд · " + item.scenario_id, "detail": "%s очков · %s" % [Text.metric(item.points), item.scenario_version], "footnote": "Рейс: " + item.trip_id, "target": item.trip_id, "action": "Открыть отчёт рекорда"})
	%Reports.present(records, "Завершённых рейсов пока нет. Начните первую тренировку.")
	for item in value.content:
		if item.id == "carriage-3":
			%FutureCarriage.present(item.unlocked)
	set_status("Профиль получен с сервера. Оценки, достижения и открытие вагона подтверждены.")
	scroll_vertical = 0

func _on_report(trip_id: String) -> void:
	report_requested.emit(trip_id)
