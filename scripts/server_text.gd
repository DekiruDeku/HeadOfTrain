extends RefCounted
## Presentation of server fields, never scoring or deciding correctness.
static func condition(value: Dictionary) -> String:
	return "Место для багажа свободно" if value.get("luggage_space") == "free" else "Место для багажа занято"

static func facts(value: Dictionary) -> String:
	var parts: Array[String] = []
	if value.has("aisle_clear"):
		parts.append("Проход свободен" if value.aisle_clear else "Проход не освобождён")
	if value.get("placement") != null:
		parts.append("Размещение: " + ("обычное место" if value.placement == "regular" else "альтернативное место"))
	if value.has("alternative_checked"):
		parts.append("Другое место проверено" if value.alternative_checked else "Другое место не проверено")
	return ". ".join(parts)

static func effects(value: Dictionary) -> String:
	var parts: Array[String] = []
	if value.has("loyalty_delta"):
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
		loyalty = value.get("loyalty", {}).get("luggage-owner", "—")
	return "Лояльность: %s   ·   Безопасность: %s" % [loyalty, value.get("safety", "—")]
