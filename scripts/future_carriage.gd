extends PanelContainer

func present(unlocked: Variant) -> void:
	%Unlock.text = "Открыт в вашем прогрессе" if unlocked == true else ("Завершите рейс, чтобы открыть вагон" if unlocked == false else "Открытие пока не подтверждено сервером")
	# Unlock is a profile reward. MVP contains no playable third-carriage trip.
	%Unavailable.disabled = true
