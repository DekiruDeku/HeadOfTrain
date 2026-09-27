extends RefCounted
## Player-facing report data. IDs remain in targets, never in copy.
const Text = preload("res://scripts/server_text.gd")
const Crew = preload("res://scripts/crew_state.gd")
const COMPETENCIES := {"communication":"Коммуникация","safety":"Безопасность","prioritization":"Приоритизация"}
const INCIDENTS := {"luggage-1":"Чемодан в проходе","blanket-1":"Нужен плед","table-1":"Уборка столика","children-1":"Шум в вагоне","seat-1":"Спор о месте"}
const STAFF := {"staff-1":"Анна","staff-2":"Борис","staff-3":"Вера","anna":"Анна","mikhail":"Михаил","elena":"Елена"}
const CRITERIA := {"check_before_promise":"Проверка условий до обещания","verify_result":"Проверка результата","identify_obstruction":"Устранение препятствия","arrival_before_deadline":"Своевременное прибытие","resolved":"Решение обращения"}

static func prose(value: Variant, fallback := "Описание не сохранено.") -> String:
	if not value is String or value.strip_edges().is_empty(): return fallback
	# Old reports may contain machine values in otherwise optional display fields.
	var regex := RegEx.new()
	regex.compile("[А-Яа-яЁё]")
	if regex.search(value) == null or value.begins_with("{") or value.begins_with("["): return fallback
	return value
static func incident(report: Dictionary, id: String) -> Dictionary:
	for item in report.get("incidents",[]):
		if str(item.get("id","")) == id: return item
	return {}
static func incident_name(report: Dictionary, id: String) -> String:
	return prose(incident(report,id).get("text"),str(INCIDENTS.get(id,"Обращение пассажира")))
static func staff_name(report: Dictionary, id: String) -> String:
	for member in report.get("staff",[]):
		if member.get("id") == id: return prose(member.get("name"),"Сотрудник бригады")
	return STAFF.get(id,"Сотрудник бригады")
static func context_text(item: Dictionary) -> String:
	var parts: Array[String] = []
	var carriage := str(item.get("carriage_id",""))
	if carriage in ["carriage-1","carriage-2","carriage-3"]: parts.append("Вагон "+carriage.right(1))
	var seat: Variant = item.get("seat",item.get("seat_number"))
	if seat is int or seat is float: parts.append("Место "+str(int(seat)))
	return " · ".join(parts)
static func elapsed(value: Variant) -> String:
	if not (value is float or value is int): return "время не записано"
	var seconds := maxi(0,roundi(float(value)))
	return "%02d:%02d" % [seconds/60,seconds%60]
static func saved_date(value: Variant) -> String:
	if not value is String or value.length() < 16: return "Дата сохранения не указана"
	var regex := RegEx.new()
	regex.compile("^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2})")
	var found := regex.search(value)
	if found == null: return "Дата сохранения не указана"
	var zone := " UTC" if value.ends_with("Z") or value.ends_with("+00:00") else ""
	return "%s.%s.%s, %s:%s%s" % [found.get_string(3),found.get_string(2),found.get_string(1),found.get_string(4),found.get_string(5),zone]
static func report_points(report: Dictionary) -> String:
	var value: Variant = report.get("points")
	if not value is Dictionary: return "Оценка этой попытки не сохранена."
	return "Очки за попытку: %s · В прогресс: +%s\nПовтор учитывает только улучшение личного рекорда." % [Text.metric(value.get("earned")),Text.metric(value.get("awarded"))]
static func violation(code: String) -> String:
	return {"aisle_left_blocked":"Проход оставлен заблокированным","unsafe_placement":"Небезопасное размещение багажа"}.get(code,"Нарушение безопасности")
static func event_name(code: String) -> String:
	return {"incident_appeared":"Поступило обращение","assignment":"Назначен проводник","arrival":"Проводник прибыл","dialog_open":"Начат разговор с пассажиром","dialog_close":"Разговор с пассажиром завершён","trip_completed":"Рейс завершён","service_completed":"Просьба пассажира выполнена","reaction_timeout":"Помощь не прибыла в срок","decision_timeout":"Время решения истекло","trip_timeout":"Рейс завершился до решения","time_speed":"Изменена скорость времени","pause":"Рейс приостановлен","resume":"Рейс продолжен"}.get(code,"Событие рейса")
static func lesson(entry: Dictionary, report: Dictionary) -> Dictionary:
	var source := str(entry.get("source","player"))
	var id := str(entry.get("incident_id",""))
	var item := incident(report,id)
	var effects: Dictionary = entry.get("effects",{})
	var choice := prose(entry.get("selected_text"),"Выбранное действие не записано.")
	var outcome := ""
	if source.ends_with("timeout"):
		choice = {"decision_timeout":"Вы не успели завершить решение за отведённое время.","reaction_timeout":"Вы не обеспечили прибытие сотрудника до срока реакции.","trip_timeout":"Вы не успели завершить обращение до окончания рейса."}.get(source,"Вы не успели завершить обращение в срок.")
		outcome = {"luggage-1":"Обращение закрыто как пропущенное. Свободный проход не подтверждён.","children-1":"Обращение закрыто как пропущенное. Договорённость с пассажирами не подтверждена.","seat-1":"Обращение закрыто как пропущенное. Вопрос с местом не решён.","blanket-1":"Обращение закрыто как пропущенное. Пассажир остался без пледа.","table-1":"Обращение закрыто как пропущенное. Просьба убрать столик не выполнена."}.get(id,"Обращение закрыто как пропущенное; помощь не завершена.")
	elif source == "service":
		choice = {"blanket-1":"Проводник принёс пассажиру плед.","table-1":"Проводник убрал посуду со столика."}.get(id,"Проводник выполнил просьбу пассажира.")
		outcome = "Обслуживание завершено, обращение закрыто."
	else:
		outcome = Text.facts(effects.get("facts",{}))
		# A final summary belongs only to the final action of this incident.
		var last := {}
		for h in report.get("history",[]):
			if h.get("incident_id") == id: last = h
		if last.get("request_id") == entry.get("request_id") and not item.is_empty():
			var summary := prose(item.get("summary"),"")
			if not summary.is_empty(): outcome = summary
		if outcome.is_empty() and "aisle_left_blocked" in effects.get("critical_marks",[]): outcome = "Багаж остался в проходе. Препятствие для пассажиров не устранено."
		if outcome.is_empty(): outcome = "Действие выполнено; отдельное изменение ситуации не зафиксировано."
	var changes: Array[String] = []
	if effects.has("loyalty_delta"): changes.append("Лояльность: "+Text.metric(effects.loyalty_delta))
	elif not effects.get("loyalty_deltas",{}).is_empty():
		var delta := 0.0
		for v in effects.loyalty_deltas.values(): delta += float(v)
		changes.append("Лояльность участников: "+Text.metric(delta))
	if effects.has("safety_delta"): changes.append("Безопасность: "+Text.metric(effects.safety_delta))
	if not changes.is_empty(): outcome += "\n"+" · ".join(changes)
	var explanation := prose(entry.get("explanation"),"")
	var advice := prose(item.get("recommendation"),{"luggage-1":"Проверьте место для багажа, помогите разместить его безопасно и убедитесь, что проход свободен.","children-1":"Выясните интересы обеих сторон и проверьте, помогла ли договорённость.","seat-1":"Проверьте билеты обоих пассажиров и подтвердите правильное размещение."}.get(id,"Учитывайте время пути сотрудника и проверяйте, выполнена ли просьба пассажира."))
	if explanation.is_empty() or explanation == choice or outcome.begins_with(explanation): explanation = advice
	if source.ends_with("timeout"):
		explanation = "Для успешного результата недостаточно начать работу: её нужно завершить в срок. "+advice
	return {"choice":choice,"outcome":outcome,"explanation":explanation}

static func journal_records(report: Dictionary) -> Array:
	var records: Array = []
	for event in report.get("events",[]):
		var lines: Array[String] = []
		var id := str(event.get("incident_id",""))
		if not id.is_empty(): lines.append(incident_name(report,id))
		var member: Variant = event.get("staff_id")
		if member is String and not member.is_empty(): lines.append("Сотрудник: "+staff_name(report,member))
		var code := str(event.get("type",""))
		var descriptions := {"incident_appeared":"Пассажир обратился за помощью. Начался отсчёт времени реакции.","assignment":"Сотруднику поручено обращение; он направляется к пассажиру.","arrival":"Сотрудник добрался до пассажира.","dialog_open":"Началось обсуждение ситуации и возможных решений.","dialog_close":"Обсуждение завершено; дальнейший результат отражён в истории действий.","service_completed":"Сотрудник закончил обслуживание пассажира.","trip_completed":"Итоги рейса сохранены."}
		lines.append(descriptions.get(code,"Событие зафиксировано в истории рейса."))
		records.append({"title":"%s · %s" % [elapsed(event.get("simulation_time")),event_name(code)],"detail":"\n".join(lines),"footnote":"Событие № %s · Время от начала рейса" % int(event.get("id",records.size()+1)),"event_id":int(event.get("id",0)),"simulation_time":event.get("simulation_time",0)})
	# Player choices are part of the readable timeline, not stand-alone assessments.
	for i in report.get("history",[]).size():
		var entry: Dictionary = report.history[i]
		var copy := lesson(entry,report)
		records.append({"title":"%s · %s" % [elapsed(entry.get("simulation_time")),incident_name(report,str(entry.get("incident_id","")))],"detail":copy.choice+"\n\n"+copy.outcome,"footnote":"Действие № %s · Время от начала рейса" % (i+1),"history_index":i,"simulation_time":entry.get("simulation_time",0),"target":entry.get("request_id",""),"target_kind":"debrief","action":"Разбор решения"})
	records.sort_custom(func(a,b): return float(a.get("simulation_time",0)) < float(b.get("simulation_time",0)))
	return records

static func assessment_records(report: Dictionary) -> Array:
	var records: Array = []
	var seen := {}
	for item in report.get("competencies",[]):
		for evidence in item.get("evidence",[]):
			var id := str(evidence.get("incident_id",""))
			var criterion := str(evidence.get("criterion",""))
			var competency := str(item.get("id",evidence.get("competency","")))
			var key := competency+"/"+id+"/"+criterion
			if seen.has(key):
				var existing: Dictionary = seen[key]
				for field in ["history_indices","event_ids"]:
					for reference in evidence.get(field,[]):
						if int(reference) not in existing[field]: existing[field].append(int(reference))
				var reason := prose(evidence.get("reason"),"")
				if not reason.is_empty() and not existing.detail.contains(reason): existing.detail += "\n\n"+reason
				if not existing.event_ids.is_empty() or not existing.history_indices.is_empty():
					existing.target = key
					existing.target_kind = "journal"
					existing.action = "Проверить по журналу"
				continue
			var description := prose(evidence.get("reason"))
			if evidence.has("points"):
				description = "Оценка критерия: %s / %s\n\n" % [Text.metric(evidence.get("points")),Text.metric(evidence.get("max_points"))]+description
			var advice := prose(evidence.get("recommendation"),"")
			if not advice.is_empty() and advice != description: description += "\n\nКак улучшить: "+advice
			var record := {"title":str(CRITERIA.get(criterion,"Критерий оценки"))+" · "+incident_name(report,id),"detail":description,"footnote":str(COMPETENCIES.get(competency,"Учебный навык"))+" · Всего за рейс: %s / %s" % [Text.metric(item.get("points")),Text.metric(item.get("max_points"))],"history_indices":evidence.get("history_indices",[]).duplicate(),"event_ids":evidence.get("event_ids",[]).duplicate()}
			seen[key] = record
			# JSON numbers are floats; Godot's Array membership is type-sensitive.
			record.history_indices = record.history_indices.map(func(v): return int(v))
			record.event_ids = record.event_ids.map(func(v): return int(v))
			if not record.event_ids.is_empty() or not record.history_indices.is_empty():
				record.target = key
				record.target_kind = "journal"
				record.action = "Проверить по журналу"
			records.append(record)
		if item.get("evidence",[]).is_empty():
			records.append({"title":str(COMPETENCIES.get(item.get("id"),"Учебный навык")),"detail":"Оценка: %s / %s\nПодробные основания не сохранены." % [Text.metric(item.get("points")),Text.metric(item.get("max_points"))],"footnote":"Оценка сохранённого рейса"})
	# Older B4 reports have qualitative evidence only. Do not duplicate it in B5.
	if report.get("competencies",[]).is_empty():
		for i in report.get("history",[]).size():
			var entry: Dictionary = report.history[i]
			for evidence in entry.get("competency_evidence",[]):
				var key := str(evidence.get("competency",""))+str(entry.get("incident_id",""))+str(evidence.get("criterion",""))+str(evidence.get("reason",""))
				if seen.has(key): continue
				seen[key] = true
				records.append({"title":str(COMPETENCIES.get(evidence.get("competency"),"Учебный навык"))+" · "+incident_name(report,str(entry.get("incident_id",""))),"detail":prose(evidence.get("reason",entry.get("explanation"))),"footnote":"Качественная оценка: баллы в этом отчёте не указаны.","target":key,"target_kind":"journal","history_indices":[i],"event_ids":[],"action":"Проверить по журналу"})
	for item in report.get("scenario_scores",[]):
		records.append({"title":"Итог · "+incident_name(report,str(item.get("incident_id",""))),"detail":"%s / %s очков\nВ прогресс: +%s\nПредыдущий рекорд: %s" % [Text.metric(item.get("points")),Text.metric(item.get("max_points")),Text.metric(item.get("awarded")),Text.metric(item.get("previous_best"))],"footnote":"Сумма критериев этого обращения"})
	return records

static func incident_records(report: Dictionary) -> Array:
	var records: Array = []
	for item in report.get("incidents",[]):
		var missed := Crew.status_key(item) == "missed"
		var record := {"title":incident_name(report,str(item.get("id","")))+" · "+Crew.status_text(item),"detail":prose(item.get("summary",item.get("timeout_explanation" if missed else "success_explanation"))),"footnote":context_text(item)}
		var recommendation := prose(item.get("recommendation"),"")
		if not recommendation.is_empty(): record.detail += "\n\n"+recommendation
		for entry in report.get("history",[]):
			if entry.get("incident_id") == item.get("id"):
				record.target = entry.request_id
				record.target_kind = "debrief"
				record.action = "Разбор решения"
		records.append(record)
	return records
static func violation_records(report: Dictionary) -> Array:
	var records: Array = []
	for mark in report.get("critical_marks",[]):
		var record := {"title":violation(str(mark)),"detail":"В сохранённом рейсе отмечено нарушение безопасности. Подробности последствий не записаны.","footnote":""}
		for entry in report.get("history",[]):
			if mark in entry.get("effects",{}).get("critical_marks",[]):
				var copy := lesson(entry,report)
				record.detail = copy.outcome+"\n\n"+copy.explanation
				record.footnote = incident_name(report,str(entry.get("incident_id","")))
				record.target = entry.request_id
				record.target_kind = "debrief"
				record.action = "Показать действие"
				break
		records.append(record)
	return records
static func archive_records(values: Array, current: Dictionary = {}) -> Array:
	var records: Array = []
	var seen: Array[String] = []
	for entry in values:
		if not entry is Dictionary: continue
		var id := str(entry.get("trip_id",""))
		if id.is_empty() or id in seen: continue
		seen.append(id)
		var data: Dictionary = current if current.get("trip_id") == id else entry
		var description := "Москва — Санкт-Петербург\nСохранён: "+saved_date(entry.get("completed_at",data.get("completed_at")))
		if data.get("points") is Dictionary: description += "\n\n"+report_points(data)
		elif data.has("scales"):
			description += "\n\nЛояльность: %s · Безопасность: %s\nРешено обращений: %s" % [Text.metric(data.scales.get("overall_loyalty")),Text.metric(data.scales.get("safety")),data.get("resolved_incident_ids",[]).size()]
		else: description += "\n\nОткройте отчёт, чтобы увидеть сохранённые итоги и решения."
		records.append({"title":"Сохранённый рейс · %s" % (records.size()+1),"detail":description,"footnote":"Результаты этой попытки","target":id,"target_kind":"archive","action":"Открыть отчёт"})
	return records
