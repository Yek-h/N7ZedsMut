class N7_Boss extends KFChar.ZombieBoss_STANDARD;

/**
 * @param bCanKite          - Whether players are allowed to exploit kiting 
 * @param CGShots           - Fixed number of chaingun shots
 * @param CGFireRate        - Chaingun velocity
 * @param RLShots           - Fixed number of rockets to be shot
 * @param RLFireRate        - Rocket Launcher velocity
 */
struct CombatStage
{
    var bool bCanKite;
    var byte CGShots, RLShots;
    var float CGFireRate, RLFireRate;
};

var CombatStage CombatStages[4];

var byte MissileShotsLeft;

simulated function bool HitCanInterruptAction()
{
    return !bWaitForAnim && !bShotAnim;
}

simulated event SetAnimAction(name NewAction)
{
    if (NewAction == '')
        return;

    // 50% that Patriarch will use alternate claw animation
    if (NewAction == 'MeleeClaw' && FRand() > 0.5)
    {
        NewAction = 'MeleeClaw2';
    }

    ExpectingChannel = DoAnimAction(NewAction);

    if (Controller != None)
    {
       BossZombieController(Controller).AnimWaitChannel = ExpectingChannel;
    }

    if (AnimNeedsWait(NewAction))
    {
        bWaitForAnim = true;
    }
    else
    {
        bWaitForAnim = false;
    }

    if (Level.NetMode != NM_Client)
    {
        AnimAction = NewAction;
        bResetAnimAct = true;
        ResetAnimActTime = Level.TimeSeconds + 0.3;
    }
}

simulated function int DoAnimAction(name AnimName)
{
    // Unused MeleeClaw2 animation added
    if (
        AnimName == 'MeleeClaw' || 
        AnimName == 'MeleeClaw2' || 
        AnimName == 'MeleeImpale' || 
        AnimName == 'transition')
    {
        AnimBlendParams(1, 1.0, 0.0,, SpineBone1);
        PlayAnim(AnimName,, 0.1, 1);
        
        return 1;
    }
    else if (AnimName == 'RadialAttack')
    {
        AnimBlendParams(1, 0.0);
        PlayAnim(AnimName,, 0.1);
        return 0;
    }
    // Animation blending for moving chaingun attack
    else if (AnimName == 'FireMG')
    {
        AnimBlendParams(1, 1.0, 0.0,, FireRootBone, true);
        PlayAnim(AnimName,, 0.f, 1);
        return 1;
    }
    else if (AnimName == 'FireEndMG')
    {
        AnimBlendParams(1, 0);
    }

    Return Super.DoAnimAction(AnimName);
}

simulated function CloakBoss()
{
    local Controller C;
    local int index;

    if (bZapped)
    {
        return;
    }

    if (bSpotted)
    {
        Visibility = 120;
        if (Level.NetMode == NM_DedicatedServer)
            return;

        Skins[0] = Finalblend'KFX.StalkerGlow';
        Skins[1] = Finalblend'KFX.StalkerGlow';
        bUnlit = true;
        return;
    }

    Visibility = 0;
    bCloaked = true;
    if (Level.NetMode != NM_Client)
    {
        for (C = Level.ControllerList; C != None; C = C.NextController)
        {
            if (C.bIsPlayer && C.Enemy == Self)
                C.Enemy = None;
        }
    }

    if (Level.NetMode == NM_DedicatedServer)
        return;

    Skins[0] = Shader'KF_Specimens_Trip_N7.patriarch_invisible_gun';
    Skins[1] = Shader'KF_Specimens_Trip_N7.patriarch_invisible';

    // Invisible - no shadow
    if (PlayerShadow != None)
        PlayerShadow.bShadowActive = false;

    // Remove/disallow projectors on invisible people
    Projectors.Remove(0, Projectors.Length);
    bAcceptsProjectors = false;

    // Randomly send out a message about Patriarch going invisible(10% chance)
    if (FRand() < 0.10)
    {
        // Pick a random Player to say the message
        index = Rand(Level.Game.NumPlayers);

        for (C = Level.ControllerList; C != None; C = C.NextController)
        {
            if (PlayerController(C) != None)
            {
                if (index == 0)
                {
                    PlayerController(C).Speech('AUTO', 8, "");
                    break;
                }
                index--;
            }
        }
    }
}

function RangedAttack(Actor A)
{
    local float D;
    local bool bOnlyE, bDesireChainGun;

    if (Controller.LineOfSightTo(A) && FRand() < 0.15 && LastChainGunTime < Level.TimeSeconds)
    {
        bDesireChainGun = true;
    }

    if (bShotAnim)
    {
        return;
    }

    D = VSize(A.Location-Location);
    bOnlyE = (Pawn(A) != None && OnlyEnemyAround(Pawn(A)));

    if (IsCloseEnuf(A))
    {
        bShotAnim = true;

        if (Health > 1500 && Pawn(A) != None && FRand() < 0.5)
        {
            SetAnimAction('MeleeImpale');
        }
        else
        {
            SetAnimAction('MeleeClaw');
        }
    }
    else if (Level.TimeSeconds - LastSneakedTime > 20.0)
    {
        if (FRand() < 0.3)
        {
            LastSneakedTime = Level.TimeSeconds;
            return;
        }
        SetAnimAction('transition');
        GoToState('SneakAround');
    }
    else if (bChargingPlayer && (bOnlyE || D < 200))
    {
        return;
    }
    else if (
        !bDesireChainGun && !bChargingPlayer && 
        (D < 300 || (D < 700 && bOnlyE)) &&
        // Charge cooldown shortened
        (Level.TimeSeconds - LastChargeTime > (3.5 + 3.0 * FRand())))
    {
        SetAnimAction('transition');
        GoToState('Charging');
    }
    else if (LastMissileTime < Level.TimeSeconds && D > 500)
    {
        if (!Controller.LineOfSightTo(A) || FRand() > 0.75)
        {
            LastMissileTime = Level.TimeSeconds + FRand() * 5;
            return;
        }

        // Missile cooldown shortened
        LastMissileTime = Level.TimeSeconds + 7.5 + FRand() * 10;

        bShotAnim = true;
        Acceleration = vect(0, 0, 0);

        SetAnimAction('PreFireMissile');
        HandleWaitForAnim('PreFireMissile');

        GoToState('FireMissile');
    }
    else if (!bWaitForAnim && !bShotAnim && LastChainGunTime < Level.TimeSeconds)
    {
        if (!Controller.LineOfSightTo(A) || FRand() > 0.85)
        {
            LastChainGunTime = Level.TimeSeconds + FRand() * 4;
            return;
        }

        // Chaingun cooldown shortened
        LastChainGunTime = Level.TimeSeconds + 4 + FRand() * 6;

        bShotAnim = true;
        Acceleration = vect(0, 0, 0);
        SetAnimAction('PreFireMG');

        HandleWaitForAnim('PreFireMG');
        // More shots per chaingun attack
        MGFireCounter =  CombatStages[SyringeCount].CGShots + Rand(100);

        GoToState('FireChaingun');
    }
}

function DoorAttack(Actor A)
{
    if (!bShotAnim && A != None && Physics != PHYS_Swimming)
    {
        Controller.Target = A;
        bShotAnim = true;
        Acceleration = vect(0,0,0);

        // Melee attack is used to break doors
        HandleWaitForAnim('MeleeImpale');
        SetAnimAction('MeleeImpale');
    }
}

function TakeDamage(
    int Damage, 
    Pawn InstigatedBy, 
    Vector Hitlocation, 
    Vector Momentum, 
    Class<DamageType> DamageType, 
    optional int HitIndex)
{
    // Ignore damage instigated by other ZEDs 
    if (KFMonster(InstigatedBy) == None)
    {
        Super.TakeDamage(Damage, InstigatedBy, Hitlocation, Momentum, DamageType, HitIndex);
    }
}

function ClawDamageTarget()
{
    local Vector PushDir;
    local name Anim;
    local float Frame, Rate, UsedMeleeDamage;
    local bool bDamagedSomeone, bChargeFromKite;
    local KFHumanPawn P;
    local Actor OldTarget;

    if (MeleeDamage > 1)
    {
        UsedMeleeDamage = (MeleeDamage - (MeleeDamage * 0.05)) + (MeleeDamage * (FRand() * 0.1));
    }
    else
    {
        UsedMeleeDamage = MeleeDamage;
    }

    GetAnimParams(1, Anim, Frame, Rate);

    if (Anim == 'MeleeImpale')
    {
        MeleeRange = ImpaleMeleeDamageRange;
    }
    else
    {
        MeleeRange = ClawMeleeDamageRange;
    }

    if (Controller != None && Controller.Target != None)
        PushDir = (damageForce * Normal(Controller.Target.Location - Location));
    else
        PushDir = damageForce * Vector(Rotation);

    if (Anim == 'MeleeImpale')
    {
        bDamagedSomeone = MeleeDamageTarget(UsedMeleeDamage, PushDir);
    }
    else
    {
        OldTarget = Controller.Target;
        foreach DynamicActors(Class'KFHumanPawn', P)
        {
            if ((P.Location - Location) dot PushDir > 0.0)
            {
                Controller.Target = P;
                bDamagedSomeone = bDamagedSomeone || MeleeDamageTarget(UsedMeleeDamage, damageForce * Normal(P.Location - Location));
            }
        }
        Controller.Target = OldTarget;
    }

    MeleeRange = Default.MeleeRange;

    /**
     * Kite fix: charge if melee attack didn't hit the target
     * There's still a little chance to avoid charging
     */
    bChargeFromKite = !CombatStages[SyringeCount].bCanKite && FRand() > 0.15;

    if (bDamagedSomeone)
    {
        if (Anim == 'MeleeImpale')
        {
            PlaySound(MeleeImpaleHitSound, SLOT_Interact, 2.0);
        }
        else
        {
            PlaySound(MeleeAttackHitSound, SLOT_Interact, 2.0);
        }
    }
    else if (Controller != None && Controller.Target != None && !IsInState('Escaping') && bChargeFromKite)
    {
        GoToState('Charging');
    }
}

/** God mode + invisibility when escaping */
state Escaping
{
ignores RangedAttack;

    function BeginState()
    {
        Super.BeginState();
        bBlockActors = false;
        bIgnoreEncroachers = true;
        MotionDetectorThreat = 0;
    }

    function EndState()
    {
        Super.EndState();
        bIgnoreEncroachers = false;
        bBlockActors = true;
        MotionDetectorThreat = default.MotionDetectorThreat;
    }

    function TakeDamage(
        int Damage, 
        Pawn InstigatedBy, 
        Vector Hitlocation, 
        Vector Momentum, 
        Class<DamageType> DamageType, 
        optional int HitIndex)
    {
        // Only Commando can damage Patriarch in invisible state
        if (
            KFHumanPawn(InstigatedBy) != None && 
            KFPlayerReplicationInfo(InstigatedBy.PlayerReplicationInfo) != None &&
            KFPlayerReplicationInfo(InstigatedBy.PlayerReplicationInfo).ClientVeteranSkill == Class'KFVetCommando')
        {
            Super.TakeDamage(Damage, InstigatedBy, Hitlocation, Momentum, DamageType, HitIndex);
        }
    }
}

/** God mode + invisibility when healing */
state Healing
{
ignores RangedAttack;

    function BeginState()
    {
        Super.BeginState();
        bBlockActors = false;
        bIgnoreEncroachers = true;
        MotionDetectorThreat = 0;
        
        if (!bCloaked) 
        {
            CloakBoss();
        }
    }

    function EndState()
    {
        Super.EndState();
        bIgnoreEncroachers = false;
        bBlockActors = true;
        MotionDetectorThreat = default.MotionDetectorThreat;

        if (bCloaked)
        {
            UnCloakBoss();
        }
    }

    function TakeDamage(
        int Damage, 
        Pawn InstigatedBy, 
        Vector Hitlocation, 
        Vector Momentum, 
        Class<DamageType> DamageType, 
        optional int HitIndex)
    {
        // Only Commando can damage Patriarch in invisible state
        if (
            KFHumanPawn(InstigatedBy) != None && 
            KFPlayerReplicationInfo(InstigatedBy.PlayerReplicationInfo) != None &&
            KFPlayerReplicationInfo(InstigatedBy.PlayerReplicationInfo).ClientVeteranSkill == Class'KFVetCommando')
        {
            Super.TakeDamage(Damage, InstigatedBy, Hitlocation, Momentum, DamageType, HitIndex);
        }
    }
}

/** 
 * Constant chaingun fire + fire rate increased
 * Patriarch is moving during attack
 */
state FireChaingun
{
    function BeginState()
    {
        Super.BeginState();
        bChargingPlayer = true;
        bCanStrafe = true;
    }

    function EndState()
    {
        bChargingPlayer = false;
        bCanStrafe = false;
        Super.EndState();
    }

    function Tick(float Delta)
    {
        Super(KFMonster).Tick(Delta);

        if (bChargingPlayer)
        {
            SetGroundSpeed(GetOriginalGroundSpeed() * 1.5);
        }
        else
        {
            SetGroundSpeed(GetOriginalGroundSpeed());
        } 
    }

    function AnimEnd(int Channel)
    {
        if (MGFireCounter <= 0)
        {
            bShotAnim = true;
            Acceleration = vect(0, 0, 0);
            SetAnimAction('FireEndMG');
            HandleWaitForAnim('FireEndMG');
            GoToState('');
        }
        else
        {
            if (bFireAtWill && Channel != 1)
                return;

            if (Controller.Target != None)
                Controller.Focus = Controller.Target;

            bShotAnim = false;
            bFireAtWill = true;
            SetAnimAction('FireMG');
        }
    }

Begin:
    while (true)
    {
        if (MGFireCounter <= 0 || (MGLostSightTimeout > 0 && Level.TimeSeconds > MGLostSightTimeout))
        {
            bShotAnim = true;
            Acceleration = vect(0, 0, 0);
            SetAnimAction('FireEndMG');
            HandleWaitForAnim('FireEndMG');
            GoToState('');
        }

        if (bFireAtWill)
        {
            FireMGShot();
        }
        Sleep(CombatStages[SyringeCount].CGFireRate);
    }
}

/** Shoots multiple missiles per attack */
state FireMissile
{
    function RangedAttack(Actor A)
    {
        if (MissileShotsLeft > 1)
        {
            Controller.Target = A;
            Controller.Focus = A;
        }
    }

    function BeginState()
    {
        MissileShotsLeft = CombatStages[SyringeCount].RLShots + Rand(3);
        Acceleration = vect(0,0,0);
    }

    function EndState()
    {
        MissileShotsLeft = 0;
    }

    function AnimEnd(int Channel)
    {
        local Vector Start;
        local Rotator R;

        Start = GetBoneCoords('tip').Origin;

        if (Controller.Target == None)
        {
            Controller.Target = Controller.Enemy;
        }

        if (!SavedFireProperties.bInitialized)
        {
            SavedFireProperties.AmmoClass = Class'SkaarjAmmo';
            SavedFireProperties.ProjectileClass = Class'N7_BossLAWProj';
            SavedFireProperties.WarnTargetPct = 0.15;
            SavedFireProperties.MaxRange = 10000;
            SavedFireProperties.bTossed = false;
            SavedFireProperties.bLeadTarget = true;
            SavedFireProperties.bInitialized = true;
        }
        SavedFireProperties.bInstantHit = (SyringeCount < 1);
        SavedFireProperties.bTrySplash = (SyringeCount >= 2);

        R = AdjustAim(SavedFireProperties, Start, 100);
        PlaySound(RocketFireSound, SLOT_Interact, 2.0,, TransientSoundRadius,, false);
        Spawn(Class'N7_BossLAWProj',,, Start, R);

        bShotAnim = true;
        Acceleration = vect(0, 0, 0);
        SetAnimAction('FireEndMissile');
        HandleWaitForAnim('FireEndMissile');

        // Randomly send out a message about Patriarch shooting a rocket(5% chance)
        if (FRand() < 0.05 && Controller.Enemy != None && PlayerController(Controller.Enemy.Controller) != None)
        {
            PlayerController(Controller.Enemy.Controller).Speech('AUTO', 10, "");
        }
        
        MissileShotsLeft--;
        if (MissileShotsLeft > 0)
        {
            GoToState(, 'NextShot');
        }
        else 
        {
            GoToState('');
        }
    }

Begin:
    while (true)
    {
        Acceleration = vect(0, 0, 0);
        Sleep(0.1);
    }
NextShot:
    Acceleration = vect(0, 0, 0);
    Sleep(CombatStages[SyringeCount].RLFireRate);
    AnimEnd(0);
}

defaultproperties 
{
    MenuName="N7 Patriarch"
    CombatStages(0)=(bCanKite=true,CGShots=75,RLShots=1,CGFireRate=0.05,RLFireRate=0.75)
    CombatStages(1)=(bCanKite=false,CGShots=100,RLShots=1,CGFireRate=0.04,RLFireRate=0.75)
    CombatStages(2)=(bCanKite=false,CGShots=100,RLShots=2,CGFireRate=0.035,RLFireRate=0.5)
    CombatStages(3)=(bCanKite=false,CGShots=125,RLShots=3,CGFireRate=0.03,RLFireRate=0.25)
    ImpaleMeleeDamageRange=110.000000 // Impale attack had way too little damage range (45)
    ZappedDamageMod=1.00
    ZapResistanceScale=2.0
    ZappedSpeedMod=0.8
    DetachedArmClass=Class'N7ZedsMut.N7_SeveredArmPatriarch'
    DetachedLegClass=Class'N7ZedsMut.N7_SeveredLegPatriarch'
    DetachedHeadClass=Class'N7ZedsMut.N7_SeveredHeadPatriarch'
    DetachedSpecialArmClass=Class'N7ZedsMut.N7_SeveredRocketArmPatriarch'
    Skins(0)=Combiner'KF_Specimens_Trip_N7.gatling_cmb'
    Skins(1)=Combiner'KF_Specimens_Trip_N7.patriarch_cmb'
}