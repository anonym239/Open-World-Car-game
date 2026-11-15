# 08 – Vertical Slice: Zuordnung Spezifikation ↔ Prototyp

Der Prototyp in `game/` (Godot 4.5.1, Mobile-Renderer/Vulkan, GDScript) setzt die Architektur aus `01`–`06` im Kleinen um. Es gibt keine einzige externe Asset-Datei: Geometrie, Texturen (prozedurale Shader), Audio und UI-Icons werden zur Laufzeit erzeugt.

| Spezifikation | Prototyp-Datei | Umfang |
|---|---|---|
| Composition Root / Ladebildschirm | `scripts/core/main.gd` | Systeme erzeugen, verdrahten, Startregion synchron laden, Tests starten |
| Event-Bus (`UVMEventSubsystem`) | `scripts/autoload/events.gd` | Panic, VehicleEntered/Exited, CarjackStarted, Toast, Settings |
| Input Abstraction (`UVMInputHub`) | `scripts/autoload/input_hub.gd` | normierte Werte, Flanken-Queue, Tastatur/Gamepad, Neigung (kalibrierbar) |
| TouchRouter (`UVMTouchRouter`) | `scripts/input/touch_controls.gd` | Finger-Ownership, dynamischer Floating-Stick, Kamera-Swipe, Pedal-Gleiten, Rampen, Safe-Area, Vektor-Icons |
| Device-Tiering + DynRes | `scripts/autoload/game_config.gd`, `scripts/core/quality_manager.gd` | GPU-Heuristik, FSR 1.0, MSAA je Tier, FPS-Cap |
| CarJack-Komponente | `scripts/characters/carjack_controller.gd` | vollständige FSM aus `03` inkl. Scheibe, Fahrer herausziehen, Absprung |
| Spielerfigur | `scripts/characters/player.gd` | kamerarelative Bewegung, Sprint, Sprung, Schlag, Knockdown, K.O./Respawn |
| Prozedurales Rig + Animation | `scripts/characters/humanoid_rig.gd` | Gehen/Laufen, Sitzen, Greifen, Scheibe, Fallen, Ducken, Kampf, Schlag; weiche Pose-Blends |
| Crowd-KI | `scripts/characters/pedestrian.gd`, `pedestrian_manager.gd` | Rundwege, Panik, Flucht/Angriff, Knockdown, Adoption ausgeworfener Fahrer |
| Raycast-Fahrzeug | `scripts/vehicles/vehicle.gd` | Modell aus `05` §2 inkl. Assists, Getriebe, Licht, Alarm, Aufrichten, Schlafmodus |
| Fahrzeugmodelle | `scripts/vehicles/car_factory.gd` | 5 Typen (Limousine, Sportwagen, SUV, Kleinwagen, Taxi), Profil-Extrusion mit Radhäusern, Tür mit Scharnier |
| Verkehrs-KI | `scripts/vehicles/traffic_driver.gd`, `traffic_manager.gd` | Spurgraph, Bézier-Abbiegen, Pure Pursuit, Ampeln, Hindernis-Raycasts, Panik, Spawn/Despawn |
| Weltaufbau & Streaming | `scripts/world/city_layout.gd`, `city_chunk.gd`, `chunk_manager.gd` | deterministisches Raster, Zeitscheiben, Hysterese, Vorlauf, globale Bodenebene, Occluder |
| Licht-Budget | `scripts/world/street_light_pool.gd` | N nächste Laternen als OmniLight, stabile Zuordnung, Fades |
| Tag/Nacht + CSM | `scripts/world/environment_controller.gd` | Sonne/Mond, 4 Splits, Normal-Bias, Nebel, Glow, Himmelssteuerung |
| Wetter | `scripts/world/weather_system.gd` | Zustandsmodell aus `02` §4.1, GPU-Regen, Blitze, Screen-Drops |
| Kamera | `scripts/camera/camera_rig.gd` | SpringArm-Kollision, Blend Zu-Fuß ↔ Fahrzeug, 3 Fahrzeugmodi, Recenter, FOV, Shake |
| HUD / Menü | `scripts/ui/*.gd` | Minimap (Vektor), Tacho, Gesundheit, Hinweise, Einstellungen |
| Audio | `scripts/audio/audio_synth.gd` | Motor-, Regen- und Radio-Synthese (2 Sender) |
| Shader | `shaders/*.gdshader` | Straße (prozedurale Markierungen, Pfützen, Ringe), Fassaden, Autolack (Tropfen), Figuren/Requisiten, Ampeln, Himmel, Regen, Screen-Drops |
| Tests | `scripts/tests/smoke_test.gd`, `render_test.gd` | siehe `07` §1 |

## Bewusste Vereinfachungen gegenüber der Produktion

* **Getöntes, opakes Fahrzeugglas:** Insassen werden beim Sitzen ausgeblendet (spart Draw-Calls und Transparenz-Sortierung).
* **Keine Skelett-Animation/Motion-Matching:** prozedurale Gelenkrotationen statt Montages und Motion Warping. Die Interpolation relativ zum Fahrzeug ist identisch.
* **Flache Welt:** keine Höhenzüge, keine Innenräume. Gehwege sind kollisionsfrei bündig (keine Bordstein-Stufen → keine Clipping-Kanten).
* **Keine SSR/Reflection-Probes:** Reflexionen kommen aus der Sky-Radiance plus den spekularen Highlights der Laternenlichter.
* **Kein Schadensmodell, keine Polizei/Fahndung:** außerhalb des Slice-Umfangs (Roadmap Phase 3).

## Lokal ausführen

```bash
# Godot 4.5.1 installieren, dann:
godot --path game                         # Desktop (Maus = Touch-Emulation, Tastatur siehe README)
godot --headless --path game --fixed-fps 60 -- --smoke-test     # Gameplay-Test
godot --headless --path game -- --validate                      # alle Skripte kompilieren
```
