# 05 – Touch-Eingabe & Fahrzeug-Physics-Controller (C++ für UE5)

Beide Systeme sind engine-nah, aber übertragbar geschrieben: keine Abhängigkeit von UMG-Hit-Testing und kein Chaos-Vehicle-Plugin, nur `UPrimitiveComponent::AddForceAtLocation` und Line-Traces. Die Godot-Implementierung im Prototyp (`touch_controls.gd`, `vehicle.gd`) folgt 1:1 derselben Logik und ist per CI-Smoke-Test abgesichert.

---

## 1. Touch-Eingabe

### 1.1 Datenmodell

```cpp
// VMobileInput/Public/VMTouchTypes.h
#pragma once
#include "CoreMinimal.h"

UENUM() enum class EVMWidgetKind : uint8 { Button, Pill, Stick, LookZone };
UENUM() enum class EVMHudMode   : uint8 { OnFoot, Vehicle };

struct FVMTouchWidget
{
    FName     Id;
    EVMWidgetKind Kind = EVMWidgetKind::Button;
    FVector2D Center = FVector2D::ZeroVector;   // logische Pixel (DPI-unabhängig)
    float     Radius = 50.f;
    FBox2D    Rect   = FBox2D(ForceInit);        // für Pills (Gas/Bremse)
    uint8     ModeMask = 0b11;                   // Bit0 OnFoot, Bit1 Vehicle
    int32     Finger = INDEX_NONE;               // Besitzer
    bool      bPressed = false;
    bool      bVisible = true;
    float     HitScale = 1.18f;                  // Trefferfläche > sichtbare Fläche

    bool Hit(const FVector2D& P) const
    {
        if (!bVisible) return false;
        if (Kind == EVMWidgetKind::Pill) return Rect.ExpandBy(14.f).IsInside(P);
        return FVector2D::DistSquared(P, Center) <= FMath::Square(Radius * HitScale);
    }
};

struct FVMStickState
{
    int32     Finger = INDEX_NONE;
    FVector2D Base, Knob, Home;
    float     Radius = 95.f;
    FVector2D Value = FVector2D::ZeroVector;     // nach Deadzone + Kurve
};
```

### 1.2 Router (Finger-Ownership)

```cpp
// VMobileInput/Public/VMTouchRouter.h
UCLASS()
class VMOBILEINPUT_API UVMTouchRouter : public UGameInstanceSubsystem, public IInputProcessor
{
    GENERATED_BODY()
public:
    virtual void Initialize(FSubsystemCollectionBase&) override;   // registriert als Slate-InputPreProcessor
    void SetMode(EVMHudMode M);
    void Layout(const FVector2D& ViewportSize, const FMargin& SafeArea, float HudScale);

    // IInputProcessor: Wir sehen Touch-Events VOR jedem UMG-Widget -> kein Event-Klau
    virtual bool HandleMouseButtonDownEvent(FSlateApplication&, const FPointerEvent& E) override;
    virtual bool HandleMouseMoveEvent(FSlateApplication&, const FPointerEvent& E) override;
    virtual bool HandleMouseButtonUpEvent(FSlateApplication&, const FPointerEvent& E) override;
    virtual void Tick(const float Dt, FSlateApplication&, TSharedRef<ICursor>) override;

private:
    bool OnDown(int32 Finger, const FVector2D& P);
    void OnMove(int32 Finger, const FVector2D& P, const FVector2D& Delta);
    void OnUp(int32 Finger);
    void UpdateStick();
    void ReleaseAll();
    FVector2D ToLogical(const FVector2D& ScreenPx) const { return ScreenPx / DpiScale; }

    TArray<FVMTouchWidget> Widgets;
    TMap<FName, int32> ById;
    FVMStickState Stick;
    int32 LookFinger = INDEX_NONE;
    EVMHudMode Mode = EVMHudMode::OnFoot;
    FVector2D Viewport;
    float DpiScale = 1.f;
    float Gas = 0.f, Brake = 0.f, ButtonSteer = 0.f;
    UPROPERTY() TObjectPtr<class UVMInputHub> Hub;
};
```

```cpp
// VMobileInput/Private/VMTouchRouter.cpp (Kern)
bool UVMTouchRouter::HandleMouseButtonDownEvent(FSlateApplication&, const FPointerEvent& E)
{
    if (!E.IsTouchEvent()) return false;
    return OnDown(E.GetPointerIndex(), ToLogical(E.GetScreenSpacePosition()));
}

bool UVMTouchRouter::OnDown(int32 Finger, const FVector2D& P)
{
    // 1) Widgets haben Vorrang (in Layout-Reihenfolge, kontextuelle zuerst)
    for (FVMTouchWidget& W : Widgets)
    {
        if (!(W.ModeMask & (1 << (uint8)Mode)) || W.Finger != INDEX_NONE || !W.Hit(P)) continue;
        W.Finger = Finger; W.bPressed = true;
        Hub->PressEdge(W.Id);                                  // Tap-Aktionen als Flanke
        FPlatformMisc::PrepareMobileHaptics(EMobileHapticsType::ImpactLight);
        FPlatformMisc::TriggerMobileHaptics();
        return true;                                           // Event konsumiert
    }
    // 2) Stick-Zone (linke 42 %, nicht im oberen Viertel = Minimap)
    const bool bStickUsed = Mode == EVMHudMode::OnFoot || Hub->GetSteeringMode() == EVMSteering::Stick;
    if (bStickUsed && Stick.Finger == INDEX_NONE && P.X < Viewport.X * 0.42f && P.Y > Viewport.Y * 0.28f)
    {
        Stick.Finger = Finger;
        Stick.Base = Hub->IsDynamicStick() ? P : Stick.Home;
        Stick.Knob = P;
        UpdateStick();
        return true;
    }
    // 3) Kamera-Zone
    if (LookFinger == INDEX_NONE && P.X >= Viewport.X * 0.42f) { LookFinger = Finger; return true; }
    return false;
}

void UVMTouchRouter::OnMove(int32 Finger, const FVector2D& P, const FVector2D& Delta)
{
    if (Finger == Stick.Finger) { Stick.Knob = P; UpdateStick(); return; }
    if (Finger == LookFinger)   { Hub->AddLook(Delta); return; }
    for (FVMTouchWidget& W : Widgets)
    {
        if (W.Finger != Finger) continue;
        // Pedal-Gleiten: Daumen rollt von Gas auf Bremse und zurück, ohne abzusetzen
        if (W.Id == TEXT("Gas") || W.Id == TEXT("Brake"))
        {
            FVMTouchWidget& Other = Widgets[ById[W.Id == TEXT("Gas") ? TEXT("Brake") : TEXT("Gas")]];
            if (!W.Hit(P) && Other.Hit(P) && Other.Finger == INDEX_NONE)
            {
                W.Finger = INDEX_NONE; W.bPressed = false;
                Other.Finger = Finger; Other.bPressed = true;
            }
        }
        return;   // alle anderen Buttons: "sticky" bis Finger hoch
    }
}

void UVMTouchRouter::UpdateStick()
{
    FVector2D D = Stick.Knob - Stick.Base;
    if (D.Size() > Stick.Radius)
    {
        if (Hub->IsDynamicStick()) Stick.Base = Stick.Knob - D.GetSafeNormal() * Stick.Radius; // Floating
        D = D.GetClampedToMaxSize(Stick.Radius);
    }
    const FVector2D V = D / Stick.Radius;
    const float DeadZone = Mode == EVMHudMode::OnFoot ? 0.12f : 0.07f;
    const float M = V.Size();
    if (M < DeadZone) { Stick.Value = FVector2D::ZeroVector; return; }
    float R = (M - DeadZone) / (1.f - DeadZone);                 // Rest-Bereich normieren
    if (Mode == EVMHudMode::Vehicle) R = FMath::Pow(R, 1.35f);   // feinfühlig um die Mitte
    Stick.Value = V.GetSafeNormal() * FMath::Clamp(R, 0.f, 1.f);
}

void UVMTouchRouter::Tick(const float Dt, FSlateApplication&, TSharedRef<ICursor>)
{
    if (Mode == EVMHudMode::OnFoot)
    {
        Hub->SetMove(FVector2D(Stick.Value.X, -Stick.Value.Y));   // oben = vorwärts
        Hub->SetSprint(Widgets[ById[TEXT("Sprint")]].bPressed);
        return;
    }
    const bool bGas   = Widgets[ById[TEXT("Gas")]].bPressed;
    const bool bBrake = Widgets[ById[TEXT("Brake")]].bPressed;
    Gas   = FMath::FInterpConstantTo(Gas,   bGas   ? 1.f : 0.f, Dt, bGas   ? 1.f / 0.15f : 1.f / 0.08f);
    Brake = FMath::FInterpConstantTo(Brake, bBrake ? 1.f : 0.f, Dt, bBrake ? 1.f / 0.10f : 1.f / 0.06f);
    Hub->SetPedals(Gas, Brake, Widgets[ById[TEXT("Handbrake")]].bPressed);

    switch (Hub->GetSteeringMode())
    {
    case EVMSteering::Stick:   Hub->SetTouchSteer(Stick.Value.X); break;
    case EVMSteering::Buttons:
    {
        const float Target = (Widgets[ById[TEXT("Right")]].bPressed ? 1.f : 0.f)
                           - (Widgets[ById[TEXT("Left")]].bPressed  ? 1.f : 0.f);
        ButtonSteer = FMath::FInterpConstantTo(ButtonSteer, Target, Dt, FMath::Abs(Target) > 0 ? 3.2f : 6.f);
        Hub->SetTouchSteer(ButtonSteer);
        break;
    }
    case EVMSteering::Tilt:    Hub->SetTouchSteer(0.f); break;   // InputHub liest den Sensor selbst
    }
}
```

### 1.3 Neigungslenkung (Gyro/Gravity)

```cpp
float UVMInputHub::ComputeTiltSteer(float Dt)
{
    FVector Tilt, RotRate, Gravity, Accel;
    UGameplayStatics::GetPlayerController(this, 0)->GetInputMotionState(Tilt, RotRate, Gravity, Accel);
    if (Gravity.SizeSquared() < 0.25f) return 0.f;
    // Gravity ist bereits in Bildschirmkoordinaten (Display-Rotation kompensiert)
    float Raw = -Gravity.X / Gravity.Size() - TiltNeutral;     // Kalibrierung
    if (bTiltInvert) Raw = -Raw;
    float V = FMath::Clamp(Raw / FMath::Sin(FMath::DegreesToRadians(26.f)), -1.f, 1.f);
    if (FMath::Abs(V) < 0.06f) V = 0.f;                          // Deadzone
    TiltFiltered = FMath::Lerp(TiltFiltered, V, 1.f - FMath::Exp(-Dt * 14.f));   // Tiefpass τ≈70 ms
    return TiltFiltered;
}
```

### 1.4 Kamera-Swipe (DPI-normiert)

```cpp
void AVMCameraRig::ApplyLook(const FVector2D& LogicalDelta, float Dt)
{
    const float Sens = 0.0042f * Settings->CameraSensitivity;    // rad pro logischem Pixel
    Yaw   -= LogicalDelta.X * Sens;
    Pitch  = FMath::Clamp(Pitch - LogicalDelta.Y * Sens * (Settings->bInvertY ? -1.f : 1.f), -1.25f, 0.6f);
    IdleLookTime = LogicalDelta.IsNearlyZero() ? IdleLookTime + Dt : 0.f;   // für Auto-Recenter
}
```

**Warum logische Pixel?** Ein 20-mm-Wisch soll auf jedem Gerät dieselbe Drehung erzeugen. Rohpixel würden auf 3×-Displays dreimal schneller drehen.

---

## 2. Fahrzeug-Physics-Controller

### 2.1 Modell

```
            Front (−Z / +X UE)          Pro Rad i:
     FL ●─────────────● FR              1. Raycast Mount → Boden (Länge = Rest + R_Rad)
        │      ▲      │                 2. Kompression c = L − d
        │   CoM ●     │  (tiefgelegt)   3. Fz = k·c + d·ċ + ARB·(c_i − c_j)   (≥ 0)
        │             │                 4. Kontaktgeschwindigkeit v_p = v + ω × r
     RL ●─────────────● RR              5. Lateral:  F_y = −v_lat · g_f · m/4 / Δt   (Constraint)
            Heck                        6. Längs:    F_x = Antrieb + Bremse + Roll-/Motorwiderstand
                                        7. Reibungskreis: |(F_x, F_y)| ≤ μ · Fz
                                        8. Kraft am Kontakt (+0,8·R angehoben → weniger Wanken)
```

**Warum Geschwindigkeits-Constraint statt Pacejka für die Querkraft?** Pacejka mit Schlupfwinkel `atan2(v_lat, |v_long|)` ist bei ~0 km/h singulär. Das führt zu Zittern im Stand und Kriechen am Hang, beides typische Mobile-Bugs. Der Constraint-Ansatz entfernt pro Schritt einen Anteil `g_f` der Quergeschwindigkeit. Er ist bei jeder Geschwindigkeit stabil, und der **Reibungskreis** erzeugt das Rutschen/Driften automatisch, sobald die benötigte Kraft `μ·Fz` übersteigt. Für den Drift wird die Hinterachse per Handbremse auf `g_f = 0,1` und `μ·0,6` gesetzt.

### 2.2 Parameter (Limousine, aus `car_factory.gd`)

| Größe | Wert | Herleitung |
|---|---|---|
| Masse | 1400 kg | – |
| Federweg Ruhe / Radradius | 0,30 m / 0,34 m | – |
| Federrate k | m·g/4 / 0,085 m ≈ 40 400 N/m | statische Einfederung 8,5 cm |
| Dämpfung d | 2·0,42·√(k·m/4) ≈ 3 160 Ns/m | Dämpfungsmaß ζ = 0,42 |
| Stabilisator | 0,35·k | weniger Wanken in Kurven |
| Antrieb | 8 800 N · (1 − (v/v_max)³), RWD | v_max = 52 m/s |
| Bremse | m · 9 N/kg, kappt auf Stillstand (kein Rückwärtsrutschen) | – |
| μ (Grip) | 1,25 | Arcade, leicht über Straßenreifen |
| Luftwiderstand / Abtrieb | 0,42·v² / 1,1·v² | – |
| Schwerpunkt | (0, −0,22, +0,05) m | Überschlag-Resistenz |

### 2.3 C++ (UE5, Async Physics Tick)

```cpp
// VMobileVehicles/Public/VMRaycastVehicleComponent.h
USTRUCT(BlueprintType)
struct FVMVehicleSpec
{
    GENERATED_BODY()
    UPROPERTY(EditAnywhere) float MassKg = 1400.f;
    UPROPERTY(EditAnywhere) float WheelRadius = 34.f;      // cm
    UPROPERTY(EditAnywhere) float RestLength = 30.f;       // cm
    UPROPERTY(EditAnywhere) float StaticCompression = 8.5f;// cm
    UPROPERTY(EditAnywhere) float DampingRatio = 0.42f;
    UPROPERTY(EditAnywhere) float AntiRollFactor = 0.35f;
    UPROPERTY(EditAnywhere) float EngineForce = 880000.f;  // N·cm/s² (UE-Einheiten: kg·cm/s²)
    UPROPERTY(EditAnywhere) float MaxSpeed = 5200.f;       // cm/s
    UPROPERTY(EditAnywhere) float Grip = 1.25f;
    UPROPERTY(EditAnywhere) float DriveFront = 0.f;        // 0 = RWD, 1 = FWD
    UPROPERTY(EditAnywhere) float MaxSteerDeg = 36.f;
    UPROPERTY(EditAnywhere) TArray<FVector> WheelMounts;   // lokal, FL FR RL RR
};

UCLASS(ClassGroup=(VMobile), meta=(BlueprintSpawnableComponent))
class VMOBILEVEHICLES_API UVMRaycastVehicleComponent : public UActorComponent
{
    GENERATED_BODY()
public:
    // Normierte Eingaben (Spieler über InputHub ODER KI-Fahrer, identische Schnittstelle)
    void SetInputs(float InSteer, float InThrottle, float InBrake, bool bInHandbrake)
    { Steer = InSteer; Throttle = InThrottle; Brake = InBrake; bHandbrake = bInHandbrake; }
    void SetDriverKind(EVMDriverKind K) { DriverKind = K; }

    void AsyncPhysicsTick(float Dt, Chaos::FRigidBodyHandle_Internal* Body);  // feste 60 Hz

    float GetForwardSpeed() const { return ForwardSpeed; }
    float GetWheelVisualOffset(int32 i) const { return HitDist[i] - Spec.WheelRadius; }

    UPROPERTY(EditAnywhere) FVMVehicleSpec Spec;
private:
    float EngineCurve(float V) const;
    void  UpdateSteering(float Dt, const FVector& Vel, const FTransform& Xf);

    float Steer = 0, Throttle = 0, Brake = 0; bool bHandbrake = false;
    float SteerAngle = 0, ForwardSpeed = 0;
    float SpringK = 0, DamperC = 0, AntiRoll = 0;
    float HitDist[4] = {}, Compression[4] = {};
    bool  bContact[4] = {};
    EVMDriverKind DriverKind = EVMDriverKind::None;
};
```

```cpp
// VMobileVehicles/Private/VMRaycastVehicleComponent.cpp
void UVMRaycastVehicleComponent::BeginPlay()
{
    Super::BeginPlay();
    const float g = 981.f;                                              // cm/s²
    SpringK  = Spec.MassKg * g * 0.25f / Spec.StaticCompression;
    DamperC  = 2.f * Spec.DampingRatio * FMath::Sqrt(SpringK * Spec.MassKg * 0.25f);
    AntiRoll = SpringK * Spec.AntiRollFactor;
}

float UVMRaycastVehicleComponent::EngineCurve(float V) const
{
    const float X = FMath::Clamp(FMath::Abs(V) / Spec.MaxSpeed, 0.f, 1.f);
    return Spec.EngineForce * (1.f - X * X * X);
}

void UVMRaycastVehicleComponent::UpdateSteering(float Dt, const FVector& Vel, const FTransform& Xf)
{
    const float MaxSteer = FMath::DegreesToRadians(Spec.MaxSteerDeg);
    float Limit = MaxSteer;
    if (DriverKind == EVMDriverKind::Player)                            // Touch-Assist 1: speed-sensitive
        Limit = FMath::Lerp(MaxSteer, MaxSteer * 0.3f, FMath::Clamp(FMath::Abs(ForwardSpeed) / 3800.f, 0.f, 1.f));
    float Target = Steer * Limit;
    if (DriverKind == EVMDriverKind::Player && ForwardSpeed > 400.f && !bHandbrake)
    {                                                                   // Touch-Assist 2: Gegenlenken
        const FVector L = Xf.InverseTransformVectorNoScale(Vel);
        const float Beta = FMath::Atan2(L.Y, FMath::Max(L.X, 10.f));    // UE: X vorwärts, Y rechts
        Target += FMath::Clamp(Beta * 0.55f, -0.3f, 0.3f);
    }
    const float Rate = FMath::Abs(Target) > FMath::Abs(SteerAngle) ? 2.4f : 4.5f;   // Assist 3: Ratenlimit
    SteerAngle = FMath::FInterpConstantTo(SteerAngle, Target, Dt, Rate);
}

void UVMRaycastVehicleComponent::AsyncPhysicsTick(float Dt, Chaos::FRigidBodyHandle_Internal* Body)
{
    const FTransform Xf(Body->R(), Body->X());
    const FVector Up = Xf.GetUnitAxis(EAxis::Z), Fwd = Xf.GetUnitAxis(EAxis::X);
    const FVector Vel = Body->V(), AngVel = Body->W(), CoM = Body->X() + Body->R() * Body->CenterOfMass();
    auto PointVel = [&](const FVector& P) { return Vel + FVector::CrossProduct(AngVel, P - CoM); };

    ForwardSpeed = FVector::DotProduct(Vel, Fwd);
    UpdateSteering(Dt, Vel, Xf);

    // --- Fahrlogik: Bremse im Stand = Rückwärtsgang ---------------------------
    float Drive = 0.f, Braking = 0.f;
    const bool bFwd = Throttle > 0.05f, bBack = Brake > 0.05f;
    if (bFwd && !bBack)      { if (ForwardSpeed < -100.f) Braking = Throttle; else Drive = Throttle; }
    else if (bBack && !bFwd) { if (ForwardSpeed >  100.f) Braking = Brake;    else Drive = -Brake; }
    else if (bFwd && bBack)  { Braking = Brake; }

    // --- Raycasts ---------------------------------------------------------------
    const float RayLen = Spec.RestLength + Spec.WheelRadius;
    FHitResult Hits[4];
    FCollisionQueryParams Q(SCENE_QUERY_STAT(VMWheelTrace), false, GetOwner());
    for (int32 i = 0; i < 4; ++i)
    {
        const FVector Mount = Xf.TransformPosition(Spec.WheelMounts[i]);
        bContact[i] = GetWorld()->LineTraceSingleByChannel(Hits[i], Mount, Mount - Up * (RayLen + 5.f), ECC_VMWheel, Q)
                   && Hits[i].Distance <= RayLen;
        HitDist[i]     = bContact[i] ? Hits[i].Distance : RayLen;
        Compression[i] = RayLen - HitDist[i];
    }

    const float MWheel = Spec.MassKg * 0.25f;
    int32 Grounded = 0;
    for (int32 i = 0; i < 4; ++i)
    {
        if (!bContact[i]) continue;
        ++Grounded;
        const FVector Mount = Xf.TransformPosition(Spec.WheelMounts[i]);

        // Federbein + Dämpfer + Stabilisator
        const float CompVel = -FVector::DotProduct(PointVel(Mount), Up);
        float Fz = SpringK * Compression[i] + DamperC * CompVel;
        const int32 Other = i ^ 1;                                       // Achspartner
        if (bContact[Other]) Fz += (Compression[i] - Compression[Other]) * AntiRoll;
        Fz = FMath::Clamp(Fz, 0.f, Spec.MassKg * 981.f * 2.5f);
        Body->AddForceAtPosition(Up * Fz, Mount);                        // (Chaos: AddForce + Torque)

        // Reifen-Achsen in der Kontaktebene
        const FVector N = Hits[i].ImpactNormal;
        FVector WF = (i < 2) ? Fwd.RotateAngleAxisRad(SteerAngle, Up) : Fwd;   // UE: +Winkel = rechts
        WF = (WF - N * FVector::DotProduct(WF, N)).GetSafeNormal();
        const FVector WR = FVector::CrossProduct(N, WF);                 // UE (links-händig): rechts
        const FVector Pc = Hits[i].ImpactPoint;
        const FVector Vc = PointVel(Pc);
        const float VLong = FVector::DotProduct(Vc, WF), VLat = FVector::DotProduct(Vc, WR);

        float MaxF = Spec.Grip * Fz;
        float GF = (i < 2) ? 0.9f : 0.82f;
        if (i >= 2 && bHandbrake && DriverKind != EVMDriverKind::None && FMath::Abs(ForwardSpeed) > 300.f)
        { GF = 0.1f; MaxF *= 0.6f; }                                     // Drift
        const float Lat = -VLat * GF * MWheel / Dt;

        const float Share = (i < 2) ? Spec.DriveFront * 0.5f : (1.f - Spec.DriveFront) * 0.5f;
        float Lon = 0.f;
        if (Drive > 0.f)      Lon = Drive * EngineCurve(ForwardSpeed) * Share;
        else if (Drive < 0.f) Lon = Drive * Spec.EngineForce * 0.5f * FMath::Clamp(1.f - FMath::Abs(ForwardSpeed) / 1100.f, 0.f, 1.f) * Share;
        float BF = Braking * Spec.MassKg * 900.f * 0.25f;
        if (bHandbrake && i >= 2) BF = FMath::Max(BF, Spec.MassKg * 900.f * 0.35f);
        Lon -= FMath::Sign(VLong) * FMath::Min(BF, FMath::Abs(VLong) * MWheel / Dt);  // kappt auf Stillstand
        Lon -= VLong * 6.f * 100.f;                                                       // Rollwiderstand
        if (Drive == 0.f && Braking == 0.f) Lon -= VLong * 12.f * 100.f;                  // Motorbremse

        FVector2D F(Lon, Lat);                                           // Reibungskreis
        if (F.Size() > MaxF) F *= MaxF / F.Size();
        Body->AddForceAtPosition(WF * F.X + WR * F.Y, Pc + Up * Spec.WheelRadius * 0.8f);
    }

    const float Speed = Vel.Size();
    Body->AddForce(-Vel * Speed * 0.42f * 0.01f);                        // Luftwiderstand (cm-Skalierung)
    if (Grounded > 0) Body->AddForce(-Up * Speed * Speed * 1.1f * 0.01f);  // Abtrieb
    else              Body->AddTorque(FVector::CrossProduct(Up, FVector::UpVector) * Spec.MassKg * 2.5e4f); // Luft-Stabilisierung
    if (Speed > Spec.MaxSpeed * 1.25f) Body->SetV(Vel * (Spec.MaxSpeed * 1.25f / Speed));  // Sicherheitsnetz
}
```

**Physik-Robustheit (Anti-Bug)**

| Problem | Maßnahme |
|---|---|
| Zittern im Stand | Constraint-Querkraft statt Schlupfwinkel. Bremskraft kappt auf `|v|·m/Δt` (kein Überschwingen) |
| Erster Bodenkontakt schlägt durch | Dämpfung aus der echten Punktgeschwindigkeit, nicht aus der Differenz zum Vorframe |
| Überschlag bei Bordsteinen | tiefer Schwerpunkt, Stabilisator, Querkraft-Angriffspunkt angehoben |
| Auto bleibt auf dem Dach liegen | Auto-Aufrichten nach 2,5 s, falls `Up·Z < 0,35` ∧ `v < 2 m/s` |
| Physik-Explosion | Geschwindigkeitskappung bei 125 % v_max, Radlast-Clamp |
| CPU für 90+ parkende Autos | Schlafende Rigidbodies: `_integrate_forces` läuft nur für wache Körper; Kollision weckt automatisch |
| Fahrzeug ↔ Fußgänger „Wand-Abprall“ | Fahrzeuge kollidieren physikalisch nicht mit Figuren. Treffer per OBB-Test → Knockdown mit Impuls |

### 2.4 Getriebe & Sound-Parameter

Ein simuliertes 6-Gang-Getriebe nur für Audio und HUD: Schaltpunkte 11/20/30/41/53/70 m/s, Drehzahl 1600–6400 U/min pro Gang, Leerlauf 850 + 400·Gas. Der Motor-Synthesizer (Sägezahn + Subharmonische) nutzt `rpm` als Tonhöhe und Gas als Last.

### 2.5 KI-Fahrer (gleiche Schnittstelle)

* **Spurgraph implizit** aus dem Stadtraster (Rechtsverkehr, Spurmitte 2 m rechts der Mittellinie). Abbiegen über quadratische Bézier-Kurven durch den Spur-Schnittpunkt.
* **Pure Pursuit:** `δ = atan(2·L·sin α / l_d)` mit `l_d = 5 + 0,45·v`.
* **Längsregelung:** P-Regler auf Zielgeschwindigkeit = min(Reisetempo, Kurventempo 6,5 m/s, Ampel-Bremskurve `√(2·3,2·(d−1,5))`, Hindernis-Limit aus 2 Vorwärts-Raycasts).
* **Ampeln:** global synchronisierter Phasenplan (NS-Grün 10 s · Gelb 2,5 s · Allrot 1 s · OW-Grün 10 s · Gelb 2,5 s · Allrot 1 s). Haltelinien werden nie per Nähe übersprungen, nur wenn sie wirklich überfahren sind.
* **Stillstand im Stand ohne Rückwärtsrollen:** KI hält mit Handbremse statt mit Bremse (Bremse im Stand = Rückwärtsgang).
