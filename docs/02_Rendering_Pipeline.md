# 02 – Rendering-Pipeline, Schatten, Wetter & „Zero-Bug“-Visuals

Ziel: fotorealistische Stadt bei Tag, Nacht und Regen auf High-End-Smartphones, ohne Shader-Flimmern, Z-Fighting, Clipping, Pop-In und Ruckler durch Shader-Kompilierung.

---

## 1. Pipeline-Wahl

| Option | Bewertung für Project V-Mobile |
|---|---|
| **Mobile Forward (UE5) / Forward+** | **Gewählt für High/Mid.** Native MSAA (auf Tile-GPUs fast kostenlos), keine G-Buffer-Bandbreite, gute Transparenz (Regen, Glas). Mehrere Lichter über Clustered Forward. |
| Mobile Deferred (UE5) | Nur sinnvoll bei vielen dynamischen Lichtern. Kostet G-Buffer-Bandbreite (Thermik) und hat kein MSAA. Option für Night-Only-Szenen ab Gen-2-Geräten. |
| Lumen | Auf Mobile nicht verfügbar. Ersatz: gebackene GI + Skylight + Reflection Captures + dynamische Akzente (siehe §3). |

**UE5-Kern-CVars (High)**

```ini
r.Mobile.ShadingPath=0              ; Forward
r.Mobile.SupportGPUScene=1          ; Instanced Draws, GPU-Culling
r.Mobile.EnableClusteredReflections=1
r.Mobile.Forward.EnableClusteredLights=1
r.MSAACount=4
r.Mobile.AntiAliasing=3             ; MSAA
r.Mobile.PropagateAlpha=0
r.Mobile.TonemapSubpass=1           ; Tonemapping im Subpass (spart Bandbreite)
r.DynamicRes.OperationMode=2
r.Shaders.Optimize=1
r.PSOPrecaching=1
r.ShaderPipelineCache.Enabled=1
```

---

## 2. Schatten-Architektur

### 2.1 Cascaded Shadow Maps (Hauptsonne/Mond)

* **4 Kaskaden** (High/Mid), 2 Kaskaden (Low). Eine **einzige** Richtungslichtquelle für Sonne *und* Mond. Nachts übernimmt sie die Mondfarbe, damit es nur ein Schattenbudget gibt.
* **Split-Verteilung** (praktisch-logarithmisch, λ = 0,85) bei 140 m Schattendistanz: `0–8 m | 8–22 m | 22–56 m | 56–140 m`. Die Kaskade 0 hat damit ~3 Texel/cm bei 2048² → keine „Jaggies“ an Reifen und Füßen.
* **Stabilisierung gegen Flimmern beim Kameraschwenk:**
  1. **Bounding-Sphere** statt AABB pro Kaskade → konstante Projektionsgröße beim Drehen.
  2. **Texel-Snapping**: Die Lichtmatrix wird auf ganze Shadow-Texel quantisiert → kein „Shimmering“ beim Bewegen.
  3. **Blend-Bänder** (10 % der Kaskade) zwischen Kaskaden → keine sichtbaren Kaskadengrenzen.
* **Bias-Strategie:** *Normal-Offset-Bias* (skaliert mit Texelgröße der Kaskade) + kleiner konstanter Tiefen-Bias. Dadurch gibt es weder Shadow-Acne noch Peter-Panning (schwebende Objekte).
* **Filterung:** PCF 3×3 (Mid) / 5×5 Poisson-PCF (High), Kaskade 3 nur 2×2.
* **Fade** ab 85 % der Schattendistanz in Distance-Field-/Kapselschatten hinein (§2.3).

```cpp
// UE5: Sonnen-Setup im Code (TimeOfDaySubsystem)
Sun->SetDynamicShadowCascades(Tier == EVMTier::Low ? 2 : 4);
Sun->SetDynamicShadowDistanceMovableLight(Tier == EVMTier::High ? 14000.f : 10000.f); // cm
Sun->CascadeDistributionExponent = 2.8f;
Sun->CascadeTransitionFraction  = 0.1f;
Sun->ShadowBias      = 0.35f;
Sun->ShadowSlopeBias = 0.6f;
Sun->bUseInsetShadowsForMovableObjects = true;   // Fahrzeuge: per-Object-Schatten nah
```

Im Prototyp: `EnvironmentController` (Godot: `SHADOW_PARALLEL_4_SPLITS`, `blend_splits`, Normal-Bias 1.4, Fade 0.85).

### 2.2 Contact Shadows

* **Screen-Space Contact Shadows** (UE: `ContactShadowLength=0.02`, nur High) für Reifen↔Asphalt, Schuhe↔Gehweg, Bordsteinkanten.
* **Fallback für alle Tiers: Kapsel-/Blob-Kontaktschatten**. Ein weiches, projiziertes Decal unter jedem Fahrzeug (Breite × Länge + 30 %) und jeder Figur (Ø 1 m) verhindert *immer* schwebende Objekte, auch jenseits der CSM-Distanz.
  * Decals projizieren nur auf die Welt-Render-Layer (Figuren und Fahrzeuge liegen auf eigenem Layer), damit sie nicht auf das Objekt selbst fallen.
  * `normal_fade` 0,5 → keine Projektion auf senkrechte Wände.
  * Im Prototyp: `WorldMaterials.make_blob_shadow()`.

### 2.3 Distance-Field-Schatten / Fernschatten

* Gebäude bekommen **Mesh Distance Fields** (UE: `r.DistanceFieldShadowing=1` auf High). Jenseits von 140 m sorgen DF-Schatten für weiche, großflächige Gebäudeschatten bis 600 m.
* **Fallback (Mid/Low):** Gebackene **Gebäude-Schattenmasken** in den Lightmaps für 4 Sonnenstände (Morgen/Mittag/Abend/Nacht) mit Blend nach Tageszeit, oder rein ambienter Abfall (AO-Volumen).

---

## 3. Globale Beleuchtung ohne Lumen

| Komponente | Umsetzung |
|---|---|
| Statische GI | GPU-Lightmass, Lightmap-Dichte 0,5–2 Texel/m (Fassaden), **Volumetric Lightmap** für dynamische Objekte |
| Tageszeit | Lightmaps für *indirektes* Licht (sonnenunabhängig skaliert) + dynamische Sonne direkt; Skylight wird alle 2 s neu erfasst (zeitlich verteilt) |
| Reflexionen | Box-Reflection-Captures pro Straßenzug (gebacken für Tag/Nacht) + **SSR (High)** + **Clustered Reflection Captures**. **Planar Reflections** (aus dem Ursprungsplan für Autos) nur auf High im Fotomodus bzw. für eine einzige Wasserfläche: Sie kosten ein zweites Szenen-Rendering (+40–60 % GPU), sind auf Mobile im Spielbetrieb nicht tragbar und werden für Lack durch Captures + Matcap-Ergänzung ersetzt |
| Nachtlichter | Emissive Fenster/Neon, **Licht-Budget-Pool**: nur die N nächsten Straßenlaternen sind echte Lichter (High 7 / Mid 5 / Low 3), die übrigen leuchten emissiv + gebacken |

**Licht-Budget-Pool (implementiert: `StreetLightPool`)**

```cpp
// UE5-Skizze: UVMLightPoolSubsystem
void UVMLightPoolSubsystem::Tick(float Dt)
{
    if (NightFactor < 0.02f) { FadeAllOut(Dt); return; }
    if ((Accum += Dt) < 0.3f) return; Accum = 0.f;
    TArray<FVector, TInlineAllocator<16>> Nearest;
    LampGrid.QueryNearest(CameraPos, /*Radius*/ 6000.f, Budget, Nearest); // Spatial Hash
    // Stabile Zuordnung: belegte Slots behalten ihre Laterne -> kein Flackern
    for (FSlot& S : Slots) S.bKeep = Nearest.RemoveSingleSwap(S.Target) > 0;
    for (FSlot& S : Slots) if (!S.bKeep && Nearest.Num()) S.Retarget(Nearest.Pop()); // Fade-out -> move -> Fade-in
}
```

---

## 4. Regen- & Wettersystem

### 4.1 Zustandsmodell (physikalisch motiviert)

```
Zielzustand (CLEAR/CLOUDY/RAIN/STORM) ──► RainIntensity  τ ≈ 18 s (exponentiell)
                                         CloudCover, Storm, FogDensity  τ ≈ 18 s
RainIntensity > 0.05 ──► Wetness    += (0.02 + 0.06·Rain)·dt        (≈ 15–40 s bis nass)
                        PuddleLevel += 0.012·Rain·dt                 (≈ 80 s bis volle Pfützen)
trocken              ──► Wetness    -= 0.008·dt  (≈ 2 min)   PuddleLevel -= 0.004·dt (≈ 4 min)
```

Alle Werte gehen als **globale Shader-Parameter** an alle Materialien (UE: `Material Parameter Collection MPC_Weather`, Prototyp: `shader_globals`). Pro Frame gibt es genau **ein** Update, keine Per-Material-Updates.

### 4.2 Nass-Shader (Wetness)

Basierend auf Lagarde („Water drop“-Reihe):

1. **Porositätsabhängige Abdunklung:** `Albedo *= lerp(1, 0.5, Wetness·Porosity)`. Asphalt/Stoff: 0,5, Lack/Glas: 0,95.
2. **Rauheit → Wasserfilm:** `Roughness = lerp(R, 0.2, Wetness)`.
3. **Exposition:** Vertikale Flächen werden nur zu ~55 % nass (`exposure = 0.55 + 0.45·saturate(N.y)`), Dächer und Straßen voll. Fahrzeugunterseiten bleiben trocken.
4. **Tropfen auf Lack/Glas:** prozedurale Zellen-Tropfen über **Surface-Gradient-Bump** (Mikkelsen). Keine Tangenten nötig, funktioniert auf jeder Geometrie, wird distanzbasiert ausgeblendet (gegen Specular-Aliasing).

```hlsl
// UE5 Material-Function MF_Wetness (Custom-Node-HLSL), auch im Prototyp-Shader car.gdshader
float3 PerturbNormal_SurfGrad(float3 N, float3 P, float H)
{
    float3 dPdx = ddx(P), dPdy = ddy(P);
    float  dHdx = ddx(H), dHdy = ddy(H);
    float3 R1 = cross(dPdy, N), R2 = cross(N, dPdx);
    float  Det = dot(dPdx, R1);
    float3 Grad = sign(Det) * (dHdx * R1 + dHdy * R2);
    return normalize(abs(Det) * N - Grad);
}

void ApplyWetness(inout float3 Albedo, inout float Roughness, inout float3 N,
                  float3 WorldPos, float3 ViewPos, float Porosity, float Exposure)
{
    const float W = MPC_Weather.Wetness * Exposure;
    Albedo    *= lerp(1.0, 0.5, W * Porosity);
    Roughness  = lerp(Roughness, min(Roughness, 0.09), W);
    const float Fade = 1.0 - smoothstep(500.0, 1600.0, length(ViewPos)); // cm
    const float Drop = DropletField(WorldPos.xy * 0.09) * W * Fade;      // 0..1 Kuppe
    N = PerturbNormal_SurfGrad(N, ViewPos, Drop * 0.6);                   // 6 mm Höhe
}
```

### 4.3 Pfützen-Simulation

* **Wo:** In Vertiefungen. Die Pfützenmaske ist **statisch in der Welt verankert** (World-Space-Rauschen oder gemalte Vertex-Color-/Höhenmaske pro Straßenmesh). Dazu kommt ein **Rinnstein-Bias** (Fahrbahnränder sammeln Wasser zuerst).
* **Wie viel:** `Mask = smoothstep(T, T+0.06, Noise + GutterBias)` mit `T = 1 − 0.55·PuddleLevel`. Pfützen *wachsen* stufenlos aus den tiefsten Stellen.
* **Look:** Albedo ×0,3, Rauheit 0,03, F0 Wasser (0,02). Spiegelung von Himmel, Lichtern und Neon über Reflection Captures/SSR (High). Auf Mid/Low über die Sky-Radiance + Specular-Highlights der Laternen-Lichter → typische nasse „Lichtstreifen“ auf Asphalt.
* **Regenringe:** analytische Ringwellen in Zellen (2 Layer, versetzte Phasen), skaliert mit `RainIntensity`, ausgeblendet ab 3 cm Pixel-Footprint.
* Prototyp: `ground.gdshader`, Funktionen `ripple()` und Pfützenteil.

### 4.4 Partikel & Post

| Effekt | Umsetzung | Budget |
|---|---|---|
| Volumetrischer Regen | GPU-Partikel (Niagara GPU-Sim / Godot GPUParticles3D) in einer 44×44 m Box um die Kamera, mit Vorhalt in Fahrtrichtung (`pos += v·0,5 s`), Streifen an Geschwindigkeit ausgerichtet → **Windablenkung** sichtbar | High 7000, Mid 4000, Low 2000 Partikel |
| Regen-Okklusion | UE: Niagara-Depth-Buffer-Kollision gegen Dächer/Unterführungen; Prototyp: offenes Stadtgebiet | – |
| Screen Drops | Fullscreen-Pass mit 2 prozeduralen Tropfen-Layern (Brechung über Screen-Texture-Offset), Intensität = Regen × Kamerablick nach oben; nur High/Mid | 0,4 ms |
| Dunst/Nebel | Exponentieller Höhennebel, Dichte +0,006 (Regen) / +0,011 (Gewitter), Farbe folgt Tageszeit | – |
| Blitze | Kurze Licht- und Himmelsaufhellung (`flash`), randomisiert alle 5–14 s im Gewitter | – |

---

## 5. Anti-Bug-Protokoll („Zero-Bug Rendering“)

| Fehlerbild | Ursache | Gegenmaßnahme (verbindlich) | Im Prototyp |
|---|---|---|---|
| **Shader-Flimmern / Moiré** | Hochfrequente Muster unter Pixelgröße, Specular-Aliasing | Prozedurale Muster analytisch AA (`fwidth`-Smoothstep); ab Subpixel → Flächenmittel; **Geometric Specular AA** (Kaplanyan) in allen Master-Materialien; MSAA 4× auf Tile-GPUs; Mip-Bias 0 (nie negativ) | `ground.gdshader` `band()`, `building.gdshader` Distanz-Fade |
| **Shadow-Shimmering** | nicht stabilisierte CSM | Bounding-Sphere + Texel-Snapping + Blend-Bänder | §2.1 |
| **Z-Fighting** | koplanare Flächen (Markierungen, Decals, Türen) | Markierungen/Pfützen **im Shader** statt als Decal-Geometrie; Reverse-Z + 32-bit-Depth; Mindestabstand 1,5 cm für Anbauteile; Decals nur mit `DBuffer`/Projektions-Decals | Straßenmarkierungen komplett prozedural |
| **Clipping Kamera ↔ Welt** | Kamera dringt in Geometrie | SpringArm mit Kugel-Sweep (r = 22 cm) gegen Welt-Kollision, Near-Plane 8 cm | `CameraRig` |
| **Clipping Figur ↔ Auto** | Ein-/Aussteigen ohne Ausrichtung | **Motion Warping** auf Tür-Sockets, Kollision der Figur während der Sequenz aus, Interpolation **relativ zum Fahrzeug** (auch wenn es rollt) | `CarJackController` |
| **Pop-In** | harte LOD-/Streaming-Grenzen | HLOD + **Dithered LOD Fade**, Sichtbarkeitsbereiche mit Hysterese-Rand, Streaming-Radius > Nebel-Sichtweite, Spawn außerhalb des Frustums | `visibility_range_*`, Spawner prüfen Frustum |
| **Schwebende Objekte** | Peter-Panning, fehlender Kontakt | Normal-Bias statt großem Tiefen-Bias + Blob-Kontaktschatten | §2.2 |
| **Unsichtbare Flächen** | falsches Winding bei Prozedural-Meshes | Winding-Autokorrektur gegen Sollnormale in **jedem** Mesh-Builder | `MeshBuilder.tri_smooth()` |
| **Shader-Kompilier-Ruckler** | PSO-Erzeugung beim ersten Sichtkontakt | **PSO-Precaching** + gebündelter PSO-Cache aus QA-Runs; im Prototyp: Material-Prewarm im Ladebildschirm | `WorldMaterials.prewarm()` |
| **Verwaschene Texturen** | Late Streaming | Streaming-Pool-Budget + Priorisierung nach Fahrtrichtung, automatisierter Test (§6) | – |
| **Durch die Welt fallen** | Kollision lädt verspätet | Globale Bodenebene unabhängig von Chunks + Streaming-Vorlauf in Fahrtrichtung | `ChunkManager._ready()` |

### Geometric Specular AA (alle Master-Materialien)

```hlsl
float SpecularAA(float3 N, float Roughness)
{
    const float3 dNdx = ddx(N), dNdy = ddy(N);
    const float Variance = 0.25 * (dot(dNdx, dNdx) + dot(dNdy, dNdy));
    const float KernelRoughness = min(2.0 * Variance, 0.18);   // Clamp gegen Überglättung
    const float A = Roughness * Roughness;
    return sqrt(saturate(A + KernelRoughness));
}
```

### LOD- & Polygon-Budgets (verbindlich, per Commandlet geprüft)

| Asset-Klasse | LOD0 | LOD1 | LOD2 | LOD3/HLOD | Screen-Size-Schwellen |
|---|---|---|---|---|---|
| Spielerfahrzeug | 60k Tris | 25k | 8k | 2k | 0.6 / 0.3 / 0.12 |
| Verkehrsfahrzeug | 25k | 9k | 3k | Impostor | 0.4 / 0.18 / 0.06 |
| Figur (Haupt) | 30k | 12k | 4k | – | 0.5 / 0.2 |
| Passant | 9k | 4k | 1.2k | Mass-Impostor | 0.3 / 0.12 / 0.04 |
| Gebäude (Block) | 40k | 12k | 3k | HLOD-Zelle | 0.5 / 0.2 / 0.05 |
| Sichtbar gesamt | ≤ 1,4 Mio Tris, ≤ 900 Draw-Calls (High) / 650 (Mid) / 400 (Low) |

---

## 6. Automatisierte QA-Skripte

```python
# UE5: Content/Python/qa_texture_streaming.py  (läuft headless im CI auf Device-Farm-Captures)
import unreal, json, sys

ROUTE = "/Game/QA/Routes/Downtown_Loop"      # aufgezeichnete Kamerafahrt
MAX_WANTED_MIPS_MISSING = 1                   # max. 1 fehlende Mip-Stufe ...
MAX_MISSING_SECONDS = 0.5                     # ... für höchstens 0,5 s

def run():
    world = unreal.EditorLevelLibrary.get_editor_world()
    seq = unreal.load_asset(ROUTE)
    report = unreal.VMQAStreamingLibrary.play_route_and_sample(world, seq, sample_hz=10)
    failures = [s for s in report.samples
                if s.missing_mips > MAX_WANTED_MIPS_MISSING and s.duration > MAX_MISSING_SECONDS]
    json.dump({"failures": [f.texture_name for f in failures]}, open("streaming_report.json", "w"))
    sys.exit(1 if failures else 0)

run()
```

Weitere Commandlets:
* `VMLodBudgetCommandlet`: prüft Tri-Budgets und LOD-Schwellen pro Asset-Klasse (Tabelle oben).
* `VMPSOCoverageCommandlet`: vergleicht gesammelte PSOs der QA-Läufe mit dem gebündelten Cache. Abdeckung unter 98 % → Build rot.
* `VMShimmerCapture`: Kamera-Pan über Testszenen, Frame-Differenz-Heatmap. Auffällige Pixel-Varianz in statischen Regionen → Ticket.

Prototyp: Die CI kompiliert **alle Shader** im Render-Test über einen echten Vulkan-Pfad (Software-GPU) und bricht bei `SHADER ERROR` ab. Jeder Push erzeugt Screenshots als Artefakt (Tag klar, Dämmerung mit Regen, Nacht mit Gewitter im Auto, Morgen in der Cinematic-Kamera).

---

## 7. Dynamische Auflösung & Upscaling

* Regelkreis auf die **gemittelte GPU-Frame-Zeit** (1-s-Fenster). Über 112 % des Budgets: −5 % Skala. Unter 82 % für 4 s: +5 % Skala. Untergrenze 55 %.
* Upscaling: UE5 **TSR Mobile** bzw. **FSR 1.0** (Prototyp). Das HUD rendert immer in nativer Auflösung (separates Overlay).
* Thermik-Signal (Android `PowerManager.getThermalHeadroom`, iOS `thermalState`) senkt präventiv die Obergrenze der Skala.
