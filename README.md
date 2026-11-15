# Project V-Mobile

**Open-World-Actionspiel für Smartphones:** Car-Jacking, Raycast-Fahrzeugphysik, daumengerechte Touch-Steuerung, dynamisches Wetter mit nassen Oberflächen und Pfützen, Tag/Nacht-Zyklus mit kaskadierten Schatten. Eigene Stadt („Vespera Bay“), eigene Fahrzeugdesigns. Das Spiel orientiert sich am Genre, kopiert aber keine fremden Inhalte.

Das Repository enthält zwei Dinge:

1. **Technischer Master-Plan** (`docs/`): Spezifikation für die Produktion mit **Unreal Engine 5**, mit C++-Code-Skizzen für Touch-Input, Fahrzeugphysik und Car-Jacking.
2. **Spielbarer Vertical Slice** (`game/`, Godot 4.5.1, Mobile-Renderer): Ein GitHub-Workflow baut daraus bei **jedem Push automatisch eine Android-APK**.

[![Android APK](https://github.com/anonym239/Open-World-Car-game/actions/workflows/android-apk.yml/badge.svg)](https://github.com/anonym239/Open-World-Car-game/actions/workflows/android-apk.yml)

---

## APK herunterladen & installieren

**Am einfachsten: [Releases](https://github.com/anonym239/Open-World-Car-game/releases/latest)** → unter „Assets“ die Datei `ProjectVMobile-v….apk` direkt auf dem Handy herunterladen.

Alternativ ist jeder Build als Artefakt verfügbar: **Actions → „Android APK“ → Lauf auswählen → Artefakt `ProjectVMobile-apk-<Nr>`** (ZIP mit der APK, GitHub-Login nötig).

Installation: Auf dem Android-Gerät „Installation aus unbekannten Quellen“ für Browser/Dateimanager erlauben und die APK öffnen. Voraussetzungen: Android 7.0+ (API 24), **arm64**, Vulkan-fähige GPU empfohlen (sonst OpenGL-ES-3-Fallback).

**Neues Release erstellen:** Versionsnummer in [`RELEASE_VERSION`](RELEASE_VERSION) erhöhen (z. B. `v0.2.0`) und pushen. Der Workflow baut die APK und legt Tag + Release automatisch an (einmal pro Version). Alternativ einen Tag `v*` pushen oder den Workflow manuell mit der Eingabe `release_tag` starten.

Die APK ist **debug-signiert**. Für eine release-signierte APK diese Repository-Secrets anlegen:
`ANDROID_KEYSTORE_BASE64` (Keystore als Base64), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`. Der Workflow nutzt sie dann automatisch.

## Steuerung

| | Touch | Tastatur / Gamepad |
|---|---|---|
| Bewegen | dynamischer Stick (linke Bildschirmhälfte, erscheint unter dem Daumen) | WASD / Pfeile · linker Stick |
| Kamera | Wischen auf der rechten Hälfte | Maus-Drag · rechter Stick |
| Sprint / Sprung / Schlag | Buttons rechts | Shift / Leertaste / E |
| Einsteigen / Auto klauen | pulsierender Auto-Button (nur in Fahrzeugnähe) | F · Y |
| Gas / Bremse-Rückwärts | große Pedale unten rechts (Daumen kann zwischen ihnen gleiten) | W / S · RT / LT |
| Handbremse (Drift) | „H“ über den Pedalen | Leertaste · A |
| Lenken | Stick, Links/Rechts-Tasten oder Neigung (Menü) | A/D · linker Stick |
| Aussteigen (schnell = Absprung) | Tür-Button oben rechts | F |
| Kamera-Modus / Radio / Pause | Buttons oben rechts | C / R / Esc |

Im Pausemenü einstellbar: Lenkmodus, Stick-Typ, Grafikqualität (Auto/Niedrig/Mittel/Hoch), Wetter, Tageszeit, Empfindlichkeit, HUD-Größe, Invertierung, Vibration, FPS-Overlay, Neigungs-Kalibrierung.

## Was der Vertical Slice zeigt

* **Car-Jacking-State-Machine:** Annähern → (Scheibe einschlagen bei verschlossenen Autos, Alarm) → Tür auf → **Fahrer herausziehen** (flieht oder greift an) → einsteigen → Tür zu → fahren. Aussteigen bzw. **Absprung bei Tempo**.
* **Fahrzeugphysik:** 4 Raycast-Federbeine, Reibungskreis, Drift per Handbremse, geschwindigkeitsabhängige Lenkung, Gegenlenk-Assistent, 5 Fahrzeugtypen.
* **Lebendige Stadt:** prozedurales Chunk-Streaming, KI-Verkehr mit Ampeln und Abbiegen, Passanten mit Panik-, Flucht- und Kampfverhalten.
* **Grafik:** 4 CSM-Kaskaden, Kontaktschatten, prozedurale Straßenmarkierungen ohne Z-Fighting, beleuchtete Fenster und Neon bei Nacht, Licht-Budget für Straßenlaternen.
* **Wetter:** stufenlose Nässe, wachsende Pfützen mit Regenringen, Regentropfen auf dem Lack, GPU-Regen mit Wind, Tropfen auf der Kamera, Gewitter mit Blitzen.
* **Mobile-Technik:** Geräte-Tiering, dynamische Auflösung (FSR 1.0), MSAA, Shader-Prewarm, Safe-Area-HUD, Haptik.
* **Prozedurales Audio:** Motorsound nach Drehzahl, Regenrauschen, zwei generative Radiosender.

## Automatisierte Qualitätssicherung (bei jedem Push)

| Job | Prüft |
|---|---|
| **Export APK** | Import, Kompilierung aller Skripte, Export, Signatur (`apksigner verify`) |
| **Smoke-Test** | prüft Karosserie-Profile und spielt headless durch: Laufen, Einsteigen, Beschleunigen, Driften, Bremsen, Aussteigen, KI-Auto stoppen, Car-Jacking mit Fahrerauswurf, Absprung, Regen, Nacht, Streaming, Passanten, Physik-Integrität |
| **Render-Test** | rendert 5 Referenzszenen (Tag, Regen-Dämmerung, Gewitter-Nacht im Auto, Cinematic-Kamera, Fahrzeug-Nahaufnahme) im echten Vulkan-Mobile-Renderer (Software-GPU), bricht bei Shader-Fehlern ab, lädt Screenshots als Artefakt hoch |

## Dokumentation (`docs/`)

| Dokument | Inhalt |
|---|---|
| [01 Architektur & Engine](docs/01_Architektur_und_Engine.md) | Engine-Entscheidung, Schichten, UE5-Module, Tick-Gruppen, Frame-/Speicherbudgets, Device-Profiles |
| [02 Rendering-Pipeline](docs/02_Rendering_Pipeline.md) | Forward-Pipeline, CSM-Stabilisierung, Contact/DF-Schatten, GI ohne Lumen, Nass-Shader (HLSL), Pfützen, Regen, Anti-Bug-Protokoll, QA-Skripte, DynRes |
| [03 Car-Jacking](docs/03_CarJacking_StateMachine.md) | Zustandsdiagramm, UE5-C++-Komponente, Motion Warping, NPC-Auswurf, Absprung, Kamera, NPC-Reaktion, Randfall-Matrix |
| [04 Mobile UI/UX](docs/04_Mobile_UI_UX.md) | Thumb-Zones, Layouts Fahrzeug/Zu-Fuß mit Maßen, Lenkmodi, Safe-Area, Barrierefreiheit, Touch-Router-Ablauf |
| [05 Touch & Fahrzeugphysik](docs/05_Touch_Input_und_Fahrzeugphysik.md) | C++: TouchRouter (Finger-Ownership), Neigung, Swipe; Raycast-Vehicle-Controller (Async Physics), KI-Fahrer |
| [06 Open World & KI](docs/06_Open_World_Streaming_und_KI.md) | Weltaufbau, Streaming-Regeln, World Partition, Verkehrs- und Passanten-KI, Laufzeit-Skalierung |
| [07 QA, CI & Roadmap](docs/07_QA_Performance_CI_Roadmap.md) | Quality Gates, Performance-Budgets, CI/CD, Phasenplan, Team, Risiken |
| [08 Prototyp-Mapping](docs/08_Prototyp_Mapping.md) | welche Spezifikation in welcher Prototyp-Datei steckt, bewusste Vereinfachungen |

## Projektstruktur

```
.github/workflows/android-apk.yml   CI: APK-Export, Smoke-Test, Render-Test
.github/actions/setup-godot/        Godot + Android-Templates (gecacht)
tools/ci_import.sh                  Import + Skript-Validierung
docs/                               Technische Spezifikation (UE5)
game/                               Godot-4.5-Projekt (Vertical Slice)
  project.godot · export_presets.cfg · icon.svg · scenes/main.tscn
  shaders/                          Straße, Fassade, Lack, Figuren, Ampel, Himmel, Regen, Screen-Drops
  scripts/autoload/                 GameConfig, Events, InputHub
  scripts/core/                     main, MeshBuilder, QualityManager, WorldState
  scripts/world/                    Stadtlayout, Chunks, Streaming, Licht-Pool, Tag/Nacht, Wetter
  scripts/vehicles/                 Fahrzeugphysik, Fahrzeugmodelle, Verkehrs-KI
  scripts/characters/               Spieler, Car-Jacking-FSM, Rig, Passanten
  scripts/camera/ · input/ · ui/ · audio/ · tests/
```

Lokal starten: Godot 4.5.1 installieren, dann `godot --path game` ausführen (oder `game/project.godot` im Editor öffnen).
