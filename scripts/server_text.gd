extends RefCounted
## Presentation of server fields, never scoring or deciding correctness.
static func metric(value: Variant) -> String:
	return ("%.1f" % float(value)).trim_suffix(".0").replace(".", ",") if value != null else "—"

static func condition(value: Dictionary) -> String:
	return "Место для багажа свободно" if value.get("luggage_space") == "free" else "Место для багажа занято"

static func facts(value: Dictionary) -> String:
	var parts: Array[String] = []
	var incidents := {"luggage-1": "Багаж", "children-1": "Дети", "seat-1": "Место"}
	for id in incidents:
		if value.get(id) is Dictionary:
			var detail := facts(value[id])
			if not detail.is_empty():
				parts.append(incidents[id] + ": " + detail)
	var labels := {"conditions_checked": "Условия проверены", "agreement_verified": "Договорённость проверена", "seat_verified": "Места проверены"}
	for key in labels:
		if value.has(key) and value[key] is bool:
			parts.append(labels[key] + (": да" if value[key] else ": нет"))
	if value.has("aisle_clear"):
		parts.append("Проход свободен" if value.aisle_clear else "Проход не освобождён")
	if value.get("placement") != null:
		parts.append("Размещение: " + ("обычное место" if value.placement == "regular" else "альтернативное место"))
	if value.has("alternative_checked"):
		parts.append("Другое место проверено" if value.alternative_checked else "Другое место не проверено")
	return ". ".join(parts)

static func effects(value: Dictionary) -> String:
	var parts: Array[String] = []
	var participants := {"luggage-owner": "владелец багажа", "blanket-passenger": "пассажир с пледом", "table-passenger": "пассажир за столиком", "complainant": "пассажир с жалобой", "family": "семья", "seated-passenger": "сидящий пассажир", "seat-holder": "владелец места"}
	for id in value.get("loyalty_deltas", {}):
		parts.append("Лояльность · %s: %s" % [participants.get(id, id), metric(value.loyalty_deltas[id])])
	if value.has("loyalty_delta") and value.get("loyalty_deltas", {}).is_empty():
		parts.append("Изменение лояльности: %s" % value.loyalty_delta)
	if value.has("safety_delta"):
		parts.append("Изменение безопасности: %s" % value.safety_delta)
	if value.has("facts"):
		parts.append(facts(value.facts))
	if not value.get("critical_marks", []).is_empty():
		parts.append("Критические отметки: " + ", ".join(value.critical_marks))
	return "\n".join(parts) if not parts.is_empty() else "Изменений шкал и фактов сервер не указал."

static func scales(value: Dictionary) -> String:
	var loyalty: Variant = value.get("overall_loyalty")
	if loyalty == null:
		loyalty = value.get("loyalty", {}).get("luggage-owner")
	return "Лояльность: %s   ·   Безопасность: %s" % [metric(loyalty), metric(value.get("safety"))]
