extends RefCounted
## Presentation adapter for B3 and the historical A3 fixture tape; no simulation rules.
const POINTS := ["c1-entry", "c1-aisle", "c1-luggage", "c1-blanket", "c1-connector", "c2-connector", "c2-aisle", "c2-table", "c2-exit", "c1-desk", "c1-door", "c2-door", "c2-luggage", "c2-desk"]
const STAFF := ["anna", "mikhail", "elena"]
const B3_STAFF := ["staff-1", "staff-2", "staff-3"]
const MARKERS := ["luggage-marker", "blanket-marker", "table-marker", "children-marker", "seat-marker"]
const STATES := {"free": "Свободен", "moving": "Идёт", "serving": "Обслуживает"}
const INCIDENT_STATES := {"waiting": "Ожидает", "en_route": "Сотрудник в пути", "resolving": "Решается", "completed": "Завершено"}

static func enabled(state: Dictionary) -> bool:
	return not state.get("staff", []).is_empty()

static func seconds(value: Variant) -> String:
	if value == null:
		return "—"
	var total := ceili(maxf(0.0, float(value)))
	return "%02d:%02d" % [total / 60, total % 60]

static func number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func valid(state: Dictionary) -> bool:
	if state.get("crew_api_version") not in ["a3-draft-1", "b3-1"] or not number(state.get("simulation_time")) or not number(state.get("remaining_time")) or not state.get("paused") is bool:
		return false
	if state.staff.size() != 3 or not state.get("assignment_options") is Array:
		return false
	if state.carriages.size() != 2 or state.carriages[0].id != "carriage-1" or state.carriages[1].id != "carriage-2":
		return false
	if state.has("display_horizon") and (not number(state.display_horizon) or state.display_horizon < 0 or state.display_horizon > 2):
		return false
	var incident_ids: Array = []
	for incident in state.incidents:
		if incident.get("id") in incident_ids or incident.get("type") not in ["safety", "service", "conflict"] or incident.get("carriage_id") not in ["carriage-1", "carriage-2"]:
			return false
		incident_ids.append(incident.id)
	var ids: Array = []
	for member in state.staff:
		if not member is Dictionary or member.get("id") not in (B3_STAFF if state.get("simulation_mode") in ["crew_b3", "full_b4"] else STAFF) or member.id in ids or member.get("state") not in STATES or member.get("carriage_id") not in ["carriage-1", "carriage-2"] or member.get("route_point_id") not in POINTS or not member.get("name") is String:
			return false
		ids.append(member.id)
		if member.state == "moving":
			if not member.get("route") is Array or member.route.size() < 2 or not number(member.get("arrival_time")):
				return false
			var previous := -INF
			for point in member.route:
				if not point is Dictionary or point.get("route_point_id") not in POINTS or not number(point.get("at")) or point.at <= previous:
					return false
				previous = point.at
		if member.get("service_end_time") != null and not number(member.service_end_time):
			return false
	for option in state.assignment_options:
		if not option is Dictionary or option.get("staff_id") not in ids or option.get("incident_id") not in incident_ids or not number(option.get("eta_seconds")) or option.eta_seconds < 0:
			return false
	for incident in state.incidents:
		if incident.get("marker_id") not in MARKERS or incident.get("state") not in INCIDENT_STATES or not incident.get("text") is String:
			return false
		if incident.get("reaction_remaining") != null and not number(incident.reaction_remaining):
			return false
	if state.paused and state.get("pause_reason") != "user" and (state.get("active_dialog_id") == null or not state.get("dialog") is Dictionary):
		return false
	if state.paused and state.get("pause_reason") != "user" and state.dialog.get("incident_id") not in incident_ids:
		return false
	if state.get("dialog") is Dictionary and state.dialog.get("critical_remaining") != null and not number(state.dialog.critical_remaining):
		return false
	return true

static func eta(state: Dictionary, staff_id: String, incident_id: String) -> Variant:
	for option in state.get("assignment_options", []):
		if option.staff_id == staff_id and option.incident_id == incident_id:
			return option.eta_seconds
	return null

static func reaction(incident: Dictionary, elapsed: float) -> String:
	if incident.state == "completed":
		return status_text(incident)
	if incident.state in ["resolving", "completed"]:
		return "Сотрудник прибыл" if incident.get("arrived_at") != null else "Обращение в работе"
	var remaining: Variant = incident.get("reaction_remaining")
	if remaining == null:
		return "Срок реакции: —"
	return "Реакция: " + seconds(maxf(0, float(remaining) - elapsed)) + " · до прибытия"

static func status_key(incident: Dictionary) -> String:
	if incident.state != "completed":
		return incident.state
	match incident.get("resolution"):
		"missed", "response_timeout", "reaction_timeout", "trip_timeout", "decision_timeout": return "missed"
		"served", "resolved": return "resolved"
		"unresolved", "allowed_blocked", "not_verified", "conflict": return "issue"
	return "completed"

static func status_text(incident: Dictionary) -> String:
	var key := status_key(incident)
	if key == "missed":
		if incident.get("resolution") == "trip_timeout":
			return "Пропущено · рейс завершился до решения"
		return "Пропущено · время решения истекло" if incident.get("resolution") == "decision_timeout" else "Пропущено · помощь не прибыла в срок"
	if incident.get("resolution") == "not_verified":
		return "Завершено · результат не проверен"
	return {"resolved": "Решено", "issue": "Завершено · проблема осталась", "completed": "Завершено · итог в разборе"}.get(key, INCIDENT_STATES.get(key, "Состояние не уточнено"))

static func symbol(incident: Dictionary) -> String:
	return {"waiting": "!", "en_route": "→", "resolving": "…", "resolved": "✓", "missed": "×", "issue": "!", "completed": "·"}.get(status_key(incident), "·")

static func priority_text(incident: Dictionary) -> String:
	return {"high": "Высокий приоритет", "normal": "Обычный приоритет", "low": "Низкий приоритет"}.get(incident.get("priority"), "Приоритет не указан")

static func latest_entry(state: Dictionary, incident_id: String) -> Dictionary:
	var entries: Array = state.get("history", [])
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		if entry.get("incident_id") == incident_id:
			return entry
		# Historical B3 luggage actions did not include incident_id.
		if not entry.has("incident_id") and state.get("simulation_mode") == "crew_b3" and incident_id == "luggage-1":
			return entry
	return {}

static func visual_staff(id: String) -> String:
	var index := B3_STAFF.find(id)
	return STAFF[index] if index >= 0 else id

static func from_wire(value: Variant) -> Variant:
	if not value is Dictionary or value.get("simulation_mode") not in ["crew_b3", "full_b4"]:
		return value
	var state: Dictionary = value.duplicate(true)
	if state.get("clock_mode") != ("server_b4" if state.get("simulation_mode") == "full_b4" else "server_b3") or not number(state.get("simulation_time")) or not state.get("staff") is Array or not state.get("incidents") is Array or not state.get("assignment_options") is Array:
		return {}
	state.crew_api_version = "b3-1"
	var horizon := 2.0
	for deadline in [state.get("next_incident_time"), state.simulation_time + state.get("remaining_time", 0)]:
		if deadline != null:
			if not number(deadline):
				return {}
			horizon = minf(horizon, maxf(0, float(deadline) - float(state.simulation_time)))
	for incident in state.incidents:
		if not incident is Dictionary:
			return {}
		if incident.get("route_point_id") not in POINTS or not incident.get("id") is String or incident.get("type") not in ["service", "safety", "conflict"] or incident.get("state") not in INCIDENT_STATES:
			return {}
		incident.reaction_remaining = incident.get("reaction_time")
		for key in ["reaction_time", "service_remaining"]:
			if incident.get(key) != null:
				if not number(incident[key]):
					return {}
				horizon = minf(horizon, maxf(0, float(incident[key])))
	for member in state.staff:
		if not member is Dictionary:
			return {}
		member.service_end_time = null
		for incident in state.incidents:
			if incident.id == member.get("incident_id") and incident.get("service_remaining") != null:
				member.service_end_time = state.simulation_time + incident.service_remaining
		if member.get("state") == "moving":
			var route: Variant = member.get("route")
			if not route is Dictionary or not route.get("segments") is Array or route.segments.is_empty() or not number(route.get("arrives_at")):
				return {}
			var points: Array = []
			for segment in route.segments:
				if not segment is Dictionary or not number(segment.get("starts_at")) or not number(segment.get("ends_at")) or segment.get("from") not in POINTS or segment.get("to") not in POINTS or segment.ends_at <= segment.starts_at:
					return {}
				if points.is_empty():
					points.append({"route_point_id": segment.from, "at": segment.starts_at})
				elif points.back().route_point_id != segment.from or points.back().at != segment.starts_at:
					return {}
				points.append({"route_point_id": segment.to, "at": segment.ends_at})
			member.route = points
			member.arrival_time = route.arrives_at
			horizon = minf(horizon, maxf(0, float(route.arrives_at) - float(state.simulation_time)))
	for option in state.assignment_options:
		if not option is Dictionary:
			return {}
		option.eta_seconds = option.get("travel_seconds")
	if state.get("dialog") is Dictionary:
		# Never bind a dialog to the last of several resolving incidents.
		if not state.dialog.has("incident_id"):
			var candidates: Array = []
			for incident in state.incidents:
				if incident.type != "service" and incident.state == "resolving":
					candidates.append(incident.id)
			if candidates.size() != 1:
				return {}
			state.dialog.incident_id = candidates[0]
		state.dialog.critical_remaining = state.dialog.get("critical_decision_time")
	# Presentation stops at the next known server event; GET confirms the outcome.
	state.display_horizon = 0.0 if state.get("status") == "completed" else horizon
	return state
