extends Node
## Globaler Event-Bus (Observer-Pattern).
## Systeme (KI, HUD, Audio, Kamera) kennen sich gegenseitig nicht direkt –
## einmalige Ereignisse laufen ausschließlich über diese Signale.

## Panik-Impuls: NPCs im Radius fliehen (Car-Jacking, Schläge, Unfälle).
signal panic(origin: Vector3, radius: float)
## Spieler sitzt fahrbereit im Fahrzeug (nach Tür-zu).
signal vehicle_entered(vehicle: Node)
## Spieler hat das Fahrzeug verlassen (normal oder Absprung).
signal vehicle_exited(vehicle: Node)
## Car-Jacking-Sequenz hat begonnen (Kamera/Audio können reagieren).
signal carjack_started(vehicle: Node)
## Kurze Info-Einblendung im HUD.
signal toast(text: String, seconds: float)
## Einstellungen wurden geändert (Qualität, Steuerung, HUD-Skalierung …).
signal settings_changed
## Spieler wurde K.O. geschlagen / überfahren und wird neu platziert.
signal player_knocked_out
## Radio-Sender gewechselt.
signal radio_changed(station_name: String)
