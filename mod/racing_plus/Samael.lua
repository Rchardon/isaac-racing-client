local SamaelMod = {}

-- Includes
local g         = require("racing_plus/globals")
local Schoolbag = require("racing_plus/schoolbag")

-- Samael was originally created by Ghostbroster
-- It is heavily modified by Zamiel for Racing+
-- (and to pass the linter)

--References and junk
local samaelID = Isaac.GetPlayerTypeByName("Samael") --Character ID of Samael
local hitBoxType = 617 --Subtype of the scythe's hitbox entity (It is a subtype of a Sacrificial Dagger)
local hood = Isaac.GetCostumeIdByPath("gfx/characters/samaelhood.anm2") --Hood+horns+bandages costume
local cloak = Isaac.GetCostumeIdByPath("gfx/characters/samaelcloak.anm2") --Cloak costume
local deadEyeCountdown = 3
local zeroColor = Color(0, 0, 0, 0, 0, 0, 0)

--Wraith meter HUD sprite
local wraithMeter = Sprite()
wraithMeter:Load("gfx/samael_wraithmeter.anm2", true)
--local wraithIsCharged = false

--Static variables (can be used as tweaks/settings)
local scytheDamageMultiplier = 1.0 --Scythe damage = damage stat * this
local scytheProjectileDamageMultiplier = 1.0 --Scythe projectile damage = damage stat * this
local chargeTimeMax = 40 --Maximum number of frames to charge a projectile
local chargeTimeMid = 20 --Charge time at default fire delay (10)
local chargeTimeMin = 10 --Minimum number of frames to charge a projectile
local swingDelayCap = 30 --Cap on how high the swingDelay can be (maximum frames between scythe swings)
local knockbackMagnitude = 4 --How much of a knockback effect the scythe has
local luckCap = 15 --How much luck samael needs to get status effects 100% of the time with melee
--local maxSizeRange = 50 --How much range to get a scythe thats twice as big

--Dynamic variables (they change)
local spawned = false --Is the scythe spawned?
local scytheState = 0 --State of the scythe
local scytheScale = 1 --Size of the scythe
local scytheColor --For storing what colour the scythe should be
local chargeTime = 0 --Number of frames required to charge a projectile
local charge = 0 --Current charge (For charging a projectile)
local lastCharge = 0
--Amount charged before being released (used for mom's knife so you need to charge at least 5 frames)
local lastDirection = -1 --Saves the last attack direction in order to keep track of it while an attack is taking place
local hitPos = nil --Where the hitbox for the melee scythe should be placed
local swing = 0 --Alternating value that denotes whether the scythe is doing a left or right swing
local swingDelay = 0 --If above 0, this is the number of frames until the scythe can be swung again

local costumeEquipped = false --Are his costumes equipped?
local dying = false --Flag for dying animation (to activate custom death animation)
local itemChecks = {}
--Array for checking if certain items are held to give damage boosts (multishot items, blood clot etc)
local numItems = -1 --Number of items currently held (used to identify when you get a new item)
local canShoot = false --If false, stops the player from firing tears normally
local isaacDying = false

local hits = 0 --Number of hits the scythe made in the current swing
local properDamage = 3.5 --For keeping track of the player's proper damage stat when applying boosts
local deadEyeBoost = 0 --For keeping track of how much damage was added with deadeye
local epiphoraCounter = 0 --How many times you've swung in the same direction
local lastEpiphoraDirection = -1
local hideScythe = false --Visibly hide the scythe (used with mom's knife synergy)
local laserRingSpawned = false --For spawning tech x rings around samael when he swings
local mawSoundCanceler = 0 --For blocking the maw of the void sound effect with the Godhead synergy's light circle
--local spawnSkull = false

--Three Dollar Bill/Fruit Cake effects and other tear effect related variables
local rainbowEffects = {
  "slow",
  "fear",
  "fire",
  "confuse",
  "freeze",
  "creep",
  "poison",
  "pee",
  "charm",
}
local threeDollarBillEffect = "none"
local cakeEffects = {
  "parasite",
  "bone",
  "greed",
  "fire",
  "keeper",
  "light",
  "confuse",
  "shock",
  "freeze",
  "fear",
  "charm",
  "creep",
  "shrink",
  "fly",
  "poison",
  "slow",
}
local threeDollarBillTimer = 0
local fruitCakeEffect = "none"
local parasiteTriggered = false
local jacobTriggered = false

local wraithTime = 0 --Time left for wraith mode
local wraithCharge = 0 --How much the wraith ability has been charged (out of 100)
local wraithActive = false --Is wraith form active?
local wraithCooldown = 0 --Brief cooldown after wraith form where you still can't take damage
local lastFrameWraithCharge = 0 --% of wraith meter charged during last update
local wraithChargeCooldown = 0 --Cooldown before the wraith meter charges normally again
local wraithActivationCooldown = 0 --Minimum cooldown between wraith mode activations
local wraithChargePenalty = 0

local fireDelayPenalty = 0 --Nerfs
local fireDelayReduced = false

local scytheAnimationEndFrame = 0

function SamaelMod:PostUpdate()
  -- Local variables
  local gameFrameCount = g.g:GetFrameCount()
  local isaacFrameCount = Isaac.GetFrameCount()

  if g.p:GetPlayerType() == samaelID then --If the player is Samael
    if wraithActivationCooldown > 0 then
      wraithActivationCooldown = wraithActivationCooldown - 1
    end

    if mawSoundCanceler > 0 then
      SamaelMod:playSound(426, 0, 3)
      mawSoundCanceler = mawSoundCanceler - 1
    end

    local roomFrames = g.r:GetFrameCount() --Framecount of current room (to identify a new room)

    SamaelMod:wraithModeHandler()

    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_WRAITH_SKULL) then
      g.p:SetActiveCharge(math.ceil(wraithCharge))
      -- Mute the annoying sound effect
      g.sfx:Stop(SoundEffect.SOUND_BEEP) -- 171
    elseif g.run.schoolbag.item == CollectibleType.COLLECTIBLE_WRAITH_SKULL then
      g.run.schoolbag.charge = math.ceil(wraithCharge)
    end

    if wraithChargeCooldown > 0 then
      wraithChargeCooldown = wraithChargeCooldown - 1
    end

    if roomFrames == 1 then
      --Respawn scythe every room (It does not persist otherwise. I prefer it this way.
      -- It's easy to manage, since this is all you have to do to fix it.)
      --Isaac.SaveModData(SamaelMod, tostring(math.floor(wraithCharge))) --Also save the wraithCharge
      spawned = false
    end

    if not canShoot then
      g.p.FireDelay = 10 --Disable tears
    end

    --Custom death animation
    if g.p:GetSprite():IsPlaying("Death") then --When player dies
      if not dying then
        --Spawn the special animations entity
        local special = Isaac.Spawn(EntityType.ENTITY_SAMAEL_SPECIAL_ANIMATIONS, 0, 0,
                                    g.p.Position, g.zeroVector, g.p):ToNPC()
        special:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
        special:GetSprite():Play("Death", 1) --Play custom death animation
        special.CanShutDoors = false
        dying = true --Set dying flag
      end
      g.p:GetSprite().Color = zeroColor --Make the player invisible
    elseif dying then --If the player is not dying, and the dying flag is on
      dying = false --Turn the flag off
      g.p:GetSprite().Color = g.color
    end

    --Three Dollar Bill
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_3_DOLLAR_BILL) then
      if threeDollarBillTimer <= 0 then
        threeDollarBillTimer = 100
        math.randomseed(isaacFrameCount + gameFrameCount)
        threeDollarBillEffect = rainbowEffects[ math.random( #rainbowEffects ) ]
        SamaelMod:getScytheColor()
      else
        threeDollarBillTimer = threeDollarBillTimer - 1
      end
    else
      threeDollarBillTimer = 0
      threeDollarBillEffect = "none"
    end

    --Only spawn epic fetus targets if the fire button has been briefly held down
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS) and charge < 5 then
      g.p.FireDelay = 3
    end

    if not spawned then --If scythe is not spawned
      local scythe = Isaac.Spawn(EntityType.ENTITY_SAMAEL_SCYTHE, 0, 0, g.p.Position, g.zeroVector, g.p)
      scythe = scythe:ToNPC()
      SamaelMod:getScytheColor()
      scythe:GetSprite().Color = scytheColor
      scythe.GridCollisionClass = GridCollisionClass.COLLISION_NONE
      scythe:ClearEntityFlags(EntityFlag.FLAG_APPEAR) --Skip spawning animations
      scythe.CanShutDoors = false --Its not an enemy
      scytheState = 0 --Reset scythe state
      --Charge time persists, but set it back to the cap to trigger the flashing again if need be
      if charge > chargeTime then
        charge = chargeTime
      end
      spawned = true --Scythe is spawned
      laserRingSpawned = false
    end

    if chargeTime == 0 then --Set charge time on init (only really activates upon using the luamod command)
      SamaelMod:calcChargeTime()
    end

    --Replace deadeye with a custom item for samael
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_DEAD_EYE) then
      g.p:RemoveCollectible(CollectibleType.COLLECTIBLE_DEAD_EYE)
      Isaac.DebugString("Removing collectible " .. CollectibleType.COLLECTIBLE_DEAD_EYE)
      g.p:AddCollectible(CollectibleType.COLLECTIBLE_SAMAEL_DEAD_EYE, 0, false)
    end
    --Replace chocolate milk with a custom item for samael
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_CHOCOLATE_MILK) then
      g.p:RemoveCollectible(CollectibleType.COLLECTIBLE_CHOCOLATE_MILK)
      Isaac.DebugString("Removing collectible " .. CollectibleType.COLLECTIBLE_CHOCOLATE_MILK)
      g.p:AddCollectible(CollectibleType.COLLECTIBLE_SAMAEL_CHOCOLATE_MILK, 0, false)
    end
    --Replace Dr Fetus with a custom item if brimstone is also aquired
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) and
       g.p:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS) then

      g.p:RemoveCollectible(CollectibleType.COLLECTIBLE_DR_FETUS)
      Isaac.DebugString("Removing collectible " .. CollectibleType.COLLECTIBLE_DR_FETUS)
      g.p:AddCollectible(CollectibleType.COLLECTIBLE_SAMAEL_DR_FETUS, 0, false)
    elseif not g.p:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) and
           g.p:HasCollectible(CollectibleType.COLLECTIBLE_SAMAEL_DR_FETUS) then

      g.p:RemoveCollectible(CollectibleType.COLLECTIBLE_SAMAEL_DR_FETUS)
      Isaac.DebugString("Removing collectible " .. tostring(CollectibleType.COLLECTIBLE_SAMAEL_DR_FETUS) ..
                        " (Samael Dr. Fetus)")
      g.p:AddCollectible(CollectibleType.COLLECTIBLE_DR_FETUS, 0, false)
    end
    --Marked is awful, replace it
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_MARKED) then
      g.p:RemoveCollectible(CollectibleType.COLLECTIBLE_MARKED)
      Isaac.DebugString("Removing collectible " .. CollectibleType.COLLECTIBLE_MARKED)
      g.p:AddCollectible(CollectibleType.COLLECTIBLE_SAMAEL_MARKED, 0, false)
    end
    --Cursed eye + dr fetus doesnt work, so lets just get rid of the shitty item
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_CURSED_EYE) and
       g.p:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS) then

      g.p:RemoveCollectible(CollectibleType.COLLECTIBLE_CURSED_EYE)
      Isaac.DebugString("Removing collectible " .. CollectibleType.COLLECTIBLE_CURSED_EYE)
    end

    --Checking for certain items that are incompatable with Samael's standard scythe swing,
    --and granting bonus damage for them
    if numItems ~= g.p:GetCollectibleCount() then
      local itemChecksNew = {
        g.p:GetCollectibleNum(CollectibleType.COLLECTIBLE_CHEMICAL_PEEL),
        g.p:GetCollectibleNum(CollectibleType.COLLECTIBLE_BLOOD_CLOT),
        g.p:GetCollectibleNum(CollectibleType.COLLECTIBLE_CUPIDS_ARROW),
        g.p:GetCollectibleNum(CollectibleType.COLLECTIBLE_SAGITTARIUS),
        g.p:GetCollectibleNum(CollectibleType.COLLECTIBLE_LUMP_OF_COAL) * 2,
      }
      if numItems == -1 then --Resetting after player init
        itemChecks = {}
        for i = 1, #itemChecksNew do
          itemChecks[i] = 0
        end
      end
      for i = 1, #itemChecks do --Check if any of the values have changed
        if itemChecks[i] ~= itemChecksNew[i] then
          g.p:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
          break
        end
      end
      itemChecks = itemChecksNew
      numItems = g.p:GetCollectibleCount()
      g.p:EvaluateItems()
    end
  else
    --Make sure custom items do not persist outside of Samael
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_SAMAEL_DEAD_EYE) then
      g.p:RemoveCollectible(CollectibleType.COLLECTIBLE_SAMAEL_DEAD_EYE)
      Isaac.DebugString("Removing collectible " .. tostring(CollectibleType.COLLECTIBLE_SAMAEL_DEAD_EYE) ..
                        " (Samael Dead Eye)")
      g.p:AddCollectible(CollectibleType.COLLECTIBLE_DEAD_EYE, 0, false)
    end
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_SAMAEL_CHOCOLATE_MILK) then
      g.p:RemoveCollectible(CollectibleType.COLLECTIBLE_SAMAEL_CHOCOLATE_MILK)
      Isaac.DebugString("Removing collectible " .. tostring(CollectibleType.COLLECTIBLE_SAMAEL_CHOCOLATE_MILK) ..
                        " (Samael Chocolate Milk)")
      g.p:AddCollectible(CollectibleType.COLLECTIBLE_CHOCOLATE_MILK, 0, false)
    end
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_SAMAEL_DR_FETUS) then
      g.p:RemoveCollectible(CollectibleType.COLLECTIBLE_SAMAEL_DR_FETUS)
      Isaac.DebugString("Removing collectible " .. tostring(CollectibleType.COLLECTIBLE_SAMAEL_DR_FETUS) ..
                        " (Samael Dr. Fetus)")
      g.p:AddCollectible(CollectibleType.COLLECTIBLE_DR_FETUS, 0, false)
    end
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_SAMAEL_MARKED) then
      g.p:RemoveCollectible(CollectibleType.COLLECTIBLE_SAMAEL_MARKED)
      Isaac.DebugString("Removing collectible " .. tostring(CollectibleType.COLLECTIBLE_SAMAEL_MARKED) ..
                        " (Samael Marked)")
      g.p:AddCollectible(CollectibleType.COLLECTIBLE_MARKED, 0, false)
    end
    if not g.p:GetSprite():IsPlaying("Death") and dying then
      dying = false --Turn the flag off
      g.p:GetSprite().Color = g.color
    end
    if costumeEquipped then
      g.p:TryRemoveNullCostume(cloak)
      g.p:TryRemoveNullCostume(hood)
      costumeEquipped = false
    end
    --if spawnSkull then spawnSkull = false end
  end
end

--------Wraith mode functionalities--------
function SamaelMod:wraithModeHandler()
  local roomFrameCount = g.r:GetFrameCount()
  --Framecount of current room (to identify a new room)

  --Stop wraith form
  if wraithActive and
     (g.p:GetSprite():IsPlaying("Trapdoor") or
      roomFrameCount == 1 or
      dying or
      isaacDying or
      not g.p:HasCollectible(CollectibleType.COLLECTIBLE_WRAITH_SKULL)) then

    SamaelMod:triggerWraithModeEnd()
  end
  if wraithCooldown > 0 then --On cooldown after wraith form wears off (briefly flashing and still invulnerable)
    wraithCooldown = wraithCooldown - 1
    if wraithCooldown % 4 == 0 then
      g.p:SetColor(Color(0.6,0.3,0.3,0.4,0,0,0), 2, 990, false, false)
    end
    if wraithCooldown == 0 then
      wraithActive = false
    end

  elseif wraithActive then --Full wraith form is active
    wraithTime = wraithTime - 1
    wraithCharge = 0
    g.p:GetSprite().Color = zeroColor
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.DARK_BALL_SMOKE_PARTICLE, 0,
                g.p.Position, g.zeroVector, g.p) --Smoke trail
    if wraithTime == 0 then --When wraith time is over
      wraithCooldown = 24
      g.p.MoveSpeed = g.p.MoveSpeed - 0.3
      --Isaac.DebugString("Decreased speed from the Wraith ability being over: " .. tostring(player.MoveSpeed))
      g.p.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
      SamaelMod:playSound(316, 1.8, 1.25)
      --Black poof effect
      local poof = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF02, 0,
                               g.p.Position, g.zeroVector, g.p):ToEffect()
      poof:GetSprite().Color = Color(0, 0, 0, 0.66, 0, 0, 0)
      poof:FollowParent(g.p)
    end
  end
end

function SamaelMod:triggerWraithModeEnd()
  if dying then
    g.p:SetColor(zeroColor, 57, 999, false, false)
  end
  if wraithCooldown == 0 then
    g.p.MoveSpeed = g.p.MoveSpeed - 0.3
    --Isaac.DebugString("Decreased speed from the Wraith ability being over (inside triggerWraithModeEnd function): " ..
                      --tostring(player.MoveSpeed))
  end
  wraithActive = false
  wraithCooldown = 0
  wraithTime = 0
  g.p:GetSprite().Color = g.color
  g.p.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
  Isaac.DebugString("Ended wraith mode.")
end

-----------NPC update function for the scythe entity-----------
function SamaelMod:scytheUpdate(scythe)
  -- Local variables
  local gameFrameCount = g.g:GetFrameCount()
  local isaacFrameCount = Isaac.GetFrameCount()

  scythe = scythe:ToNPC()

  if g.p:GetPlayerType() ~= samaelID then
    scythe:Remove()
    return
  end
  if dying then
    return
  end

  local hitBox --Local variable to store reference to hitbox entity
  if scythe.Child == nil then --If the scythe has no child (no spawned hitbox)
    hitBox = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.SACRIFICIAL_DAGGER, hitBoxType,
                         g.p.Position, g.zeroVector, scythe) --Spawn the hitbox
    hitBox:ClearEntityFlags(EntityFlag.FLAG_APPEAR) --Skip appear animations
    hitBox = hitBox:ToFamiliar()
    scythe.Child = hitBox --Set it as the scythe's child
    hitBox.Parent = scythe --Set the scythe as its parent
    hitBox.CollisionDamage = 0 --No Collision damage until activated
    hitBox.Coins = -1
    --Coins is used to store directions, because the actual direction-related attributes
    --were crashing my game for some reason
    hitBox.Size = 40 --Set its size (how big of a radius)
    hitBox.Position = g.zeroVector --Move it off of the screen
    hitBox.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ENEMIES
  else
    hitBox = scythe.Child:ToFamiliar() --If scythe has a child, then the hitbox exists. Set this as a reference to it
  end
  local sprite = scythe:GetSprite() --The Scythe's sprite
  local headDirection = g.p:GetHeadDirection()
  local fireDirection = g.p:GetFireDirection()
  local direction = -1
  local projVel = g.zeroVector --For storing the proper velocity of a projectile (calculated later)
  --local proj = nil --For storing a projectile when fired

  --Keep the scythe on the player
  scythe.Position = Vector(g.p.Position.X, g.p.Position.Y)
  scythe.Velocity = g.p.Velocity

  if swingDelay > 0 then --Decrement the swingdelay (if it exists)
    swingDelay = swingDelay - 1
  end

  --Spawn a tech x laser around Samael when he swings his scythe with that item acquired
  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_TECH_X) then
    if scythe.Target == nil then
      laserRingSpawned = false
    end
    if not laserRingSpawned and scytheState == 2 then
      local laser = g.p:FireTechXLaser(g.p.Position, g.zeroVector, 66):ToLaser()
      laser.Parent = scythe
      if laser.Variant ~= 2 then
        laser.Variant = 2
        laser.SpriteScale = Vector(0.5, 1)
      end
      laser.TearFlags = laser.TearFlags | 1 << 36
      laser.CollisionDamage = laser.CollisionDamage*0.3
      scythe.Target = laser
      laserRingSpawned = true
    end
  end

  --Hide the scythe whenever it is "thrown" via the mom's knife synergy
  if hideScythe or isaacDying then
    scythe:GetSprite().Color = Color(0,0,0,0,0,0,0)
    swingDelay = 4
  else
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_SAMAEL_DEAD_EYE) and
       not g.p:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then --Set redness for deadEye boost

      scytheColor.RO = (deadEyeBoost/properDamage)/2
    end
    scythe:GetSprite().Color = scytheColor --Set colour
  end

  if hideScythe and not g.p:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
    hideScythe = false
  end

  --scytheState 0 = Idle, not attacking
  --scytheState 1 = Ready/Charging, holding down an attack direction (holding up the scythe)
  --scytheState 2 = Swinging the scythe

  --READY ATTACK: When the player is holding down a fire direction, and the scythe is not on cooldown
  if fireDirection ~= -1 and swingDelay == 0 then
    if not canShoot or g.p:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
      if charge < chargeTime then --Make the scythe being held up, unless the projectile attack is charged...
        if scytheScale >= 1.5 then
          sprite:SetFrame("BigSwing", 0) --Play scythe swing animation
        else
          sprite:SetFrame("Swing", 0) --Play scythe swing animation
        end
      elseif charge == chargeTime then --If the player has been charging long enough to fire a projectile, flash red
        if not g.p:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
          if scytheScale >= 1.5 then
            sprite:Play("BigCharge", 1)
          else
            sprite:Play("Charge", 1)
          end
        end
      end
      if not hideScythe then
        charge = charge+1 --Add charge
      end
    else
      if g.p:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS) then
        charge = charge + 1 --Add charge
      end
      if scytheScale >= 1.5 then
        sprite:Play("BigIdle", 1)
      else
        sprite:Play("Idle", 1)
      end
    end

    if scytheState == 2 then --If previous attack was interrupted (due to fast attack rate)
      hitBox.Coins = -1 --Reset hitbox (explained more later)
      hitBox.CollisionDamage = 0
      SamaelMod:deadEyeFunc(true)
      if swing == 0 then --Switch 'swing' value (left or right swing)
        swing = 1
      else
        swing = 0
      end
    end

    scytheState = 1 --Scythe is ready, or charging
    lastDirection = fireDirection --Update with current attack direction
    direction = lastDirection --Current direction for rendering
  end


  --INITIATE ATTACK: When the player releases the fire direction, swing the scythe
  if fireDirection == -1  and scytheState == 1 then
    -- Do not fire a projectile when player picks something up
    if g.p:IsHoldingItem() then
      charge = 0
    end

    --If they were charging long enough to fire a projectile...
    if charge >= chargeTime and
       not g.p:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) and
       not g.p:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS) then

      --Choose the velocity of the projectile based on the last fire direction before release
      if lastDirection == Direction.UP then
        projVel = Vector(0, (-1) * g.p.ShotSpeed * 10)
      elseif lastDirection == Direction.DOWN then
        projVel = Vector(0, g.p.ShotSpeed*10)
      elseif lastDirection == Direction.LEFT then
        projVel = Vector((-1) * g.p.ShotSpeed*10, 0)
      elseif lastDirection == Direction.RIGHT then
        projVel = Vector(g.p.ShotSpeed*10, 0)
      end
      projVel = projVel:__add(g.p.Velocity) --Add the players velocity to the projectile's velocity

      scythe:PlaySound(133, 1, 0, false, 0.66) --Play the tech firing sound (albeit somewhat pitch shifted)

      local numTears = SamaelMod:getNumTears()

      if numTears == 0 then --0 actually means 1 in this case
        SamaelMod:fireScytheProjectile(projVel, 0, 0, 0) --Normal shot
      elseif numTears == 2 and not g.p:HasCollectible(CollectibleType.COLLECTIBLE_THE_WIZ) then --double shot
        if lastDirection == Direction.UP or lastDirection == Direction.DOWN then
          SamaelMod:fireScytheProjectile(projVel, 0, 8, 0)
          SamaelMod:fireScytheProjectile(projVel, 0, -8, 0)
        elseif lastDirection == Direction.LEFT or lastDirection == Direction.RIGHT then
          SamaelMod:fireScytheProjectile(projVel, 0, 0, 8)
          SamaelMod:fireScytheProjectile(projVel, 0, 0, -8)
        end
      else --triple shot and above
        local arc = 20 --how wide the projectiles disperse (this value is actually half of the total angle)
        local angle
        for i=1,numTears do --For each projectile
          angle = -arc+(arc*2)*((i-1)/(numTears-1)) --Firing angle of this particular projectile
          --Apply the wiz effect (widen the angle and split into two groups)
          if g.p:HasCollectible(CollectibleType.COLLECTIBLE_THE_WIZ) then
            if i <= numTears/2 then
              angle = angle - 25
            else
              angle = angle + 25
            end
          end
          SamaelMod:fireScytheProjectile(projVel, angle, 0,0) --Fire the projectile
        end
      end

      --Loki's Horns & Mom's Eye
      local lokiTriggered = false
      if g.p:HasCollectible(CollectibleType.COLLECTIBLE_LOKIS_HORNS) or
         g.p:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_EYE) then

        math.randomseed(isaacFrameCount + gameFrameCount)
        local luck = math.floor(g.p.Luck)+2
        if luck < 1 then luck = 1 end

        if g.p:HasCollectible(CollectibleType.COLLECTIBLE_LOKIS_HORNS) then
          if luck > 9 then luck = 9 end

          if math.random(10-luck) == 1 then
            if lastDirection ~= Direction.UP then
              SamaelMod:fireScytheProjectile(Vector(0, (-1)*g.p.ShotSpeed*10):__add(g.p.Velocity), 0, 0,0) end
            if lastDirection ~= Direction.DOWN then
              SamaelMod:fireScytheProjectile(Vector(0, g.p.ShotSpeed*10):__add(g.p.Velocity), 0, 0,0) end
            if lastDirection ~= Direction.LEFT then
              SamaelMod:fireScytheProjectile(Vector((-1)*g.p.ShotSpeed*10, 0):__add(g.p.Velocity), 0, 0,0) end
            if lastDirection ~= Direction.RIGHT then
              SamaelMod:fireScytheProjectile(Vector(g.p.ShotSpeed*10, 0):__add(g.p.Velocity), 0, 0,0) end
            lokiTriggered = true
          end
        end
        if g.p:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_EYE) and not lokiTriggered then
          if luck > 4 then luck = 4 end

          if math.random(5-luck) == 1 then
            if lastDirection == Direction.UP then
              SamaelMod:fireScytheProjectile(Vector(0, g.p.ShotSpeed*10):__add(g.p.Velocity), 0, 0,0)
            elseif lastDirection == Direction.DOWN then
              SamaelMod:fireScytheProjectile(Vector(0, (-1)*g.p.ShotSpeed*10):__add(g.p.Velocity), 0, 0,0)
            elseif lastDirection == Direction.LEFT then
              SamaelMod:fireScytheProjectile(Vector(g.p.ShotSpeed*10, 0):__add(g.p.Velocity), 0, 0,0)
            elseif lastDirection == Direction.RIGHT then
              SamaelMod:fireScytheProjectile(Vector((-1)*g.p.ShotSpeed*10, 0):__add(g.p.Velocity), 0, 0,0)
            end
          end
        end
      end

    end

    lastCharge = charge
    charge = 0 --Reset charge
    if scytheScale >= 1.5 then
      sprite:Play("BigSwing", 1) --Play scythe swing animation
      -- (this is 11 frames long)
    else
      sprite:Play("Swing", 1) --Play scythe swing animation
      -- (this is 11 frames long)
    end

    --Choose fruit cake effect
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_FRUIT_CAKE) then
      math.randomseed(isaacFrameCount + gameFrameCount)
      fruitCakeEffect = cakeEffects[ math.random( #cakeEffects ) ]
    elseif fruitCakeEffect ~= "none" then
      fruitCakeEffect = "none"
    end

    --Godhead light ring
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_GODHEAD) then
      local god = g.p:SpawnMawOfVoid(25):ToLaser()
      mawSoundCanceler = 3
      SamaelMod:playSound(133, 1, 1.3)
      god.CollisionDamage = g.p.Damage*0.3
      god:SetBlackHpDropChance(0)
      local godSprite = god:GetSprite()
      godSprite:Load("gfx/007.008_light ring.anm2", true)
      godSprite:Play("LargeRedLaser", true)
    end

    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_EPIPHORA) then
      SamaelMod:epiphoraFunc() --Epiphora
    end

    swingDelay = SamaelMod:calcSwingDelay()+1 --Set new swing delay (+1 so as to not count this frame)

    scythe:PlaySound(38, 1.75, 0, false, 1.2) --Play swinging sound
    scytheState = 2 --Set state to 2 (swinging scythe)
    scytheAnimationEndFrame = gameFrameCount + 11 -- Both animations are 11 frames long
    direction = lastDirection --Set render direction to the saved firing direction
  end

  --CURRENTLY SWINGING THE SCYTHE
  if scytheState == 2 then
    direction = lastDirection
  end
  --If scythe is swinging, and the animation is between the frames where the scythe can hit enemies
  if scytheState == 2 and sprite:GetFrame() >= 1 and sprite:GetFrame() <= 5 then
     --On the first hit frame, send the attack direction to the hitBox entity and set its collision damage
    if sprite:GetFrame() == 1 then
       --I'm using Coins to store this value because the actual Direction attributes for familiars
       --was crashing the game. Oh well!
      hitBox.Coins = lastDirection
      hitBox.CollisionDamage = g.p.Damage*scytheDamageMultiplier
      if g.p:HasCollectible(CollectibleType.COLLECTIBLE_LOST_CONTACT) then
        hitBox.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
      end
      if wraithActive and
         g.p:HasCollectible(CollectibleType.COLLECTIBLE_SOY_MILK) and
         not g.p:HasCollectible(CollectibleType.COLLECTIBLE_LIBRA) then

        hitBox.CollisionDamage = hitBox.CollisionDamage * 1.75
      end
      if g.p:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS) or
         g.p:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) or
         g.p:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then

        hitBox.CollisionDamage = hitBox.CollisionDamage * 1.5
      end
      if g.p:HasCollectible(CollectibleType.COLLECTIBLE_GHOST_PEPPER) and math.random(25) == 1 then
        local flameSpeed = 10
        --Choose the velocity of the projectile based on the last fire direction before release
        if lastDirection == Direction.UP then
          projVel = Vector(0, -flameSpeed)
        elseif lastDirection == Direction.DOWN then
          projVel = Vector(0, flameSpeed)
        elseif lastDirection == Direction.LEFT then
          projVel = Vector(-flameSpeed, 0)
        elseif lastDirection == Direction.RIGHT then
          projVel = Vector(flameSpeed, 0)
        end
        projVel = projVel:__add(g.p.Velocity) --Add the players velocity to the projectile's velocity
        Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.RED_CANDLE_FLAME, 0, g.p.Position, projVel, g.p)
      end
    end
    hitPos = hitBox.Position
    if sprite:GetFrame() == 5 then --After this duration, get rid of the hitbox
      hitPos = nil
      hitBox.Coins = -1 --"No direction"
      hitBox.CollisionDamage = 0 --Remove the collision damage (just making sure it cant hurt anything)
      hitBox.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ENEMIES
      SamaelMod:deadEyeFunc(false)
    end
  elseif scytheState == 2 and
         (sprite:IsFinished("Swing") or sprite:IsFinished("BigSwing")) then --If the swinging animation finished

    sprite.Rotation = 0
    scytheState = 0
    if swing == 0 then --Switch the side of the scythe
      swing = 1
    else
      swing = 0
    end
  end

  if scytheState == 0 then --When nothing else is going on, idle state
    if scytheScale >= 1.5 then
      sprite:Play("BigIdle", 1)
    else
      sprite:Play("Idle", 1)
    end
    direction = headDirection
  end

  if dying then
    direction = Direction.DOWN
    if scytheScale >= 1.5 then
      sprite:Play("BigIdle", 1)
    else
      sprite:Play("Idle", 1)
    end
    hitBox.CollisionDamage = 0
  end

  scythe.RenderZOffset = 0
  --Render the scythe at the correct angle and whatnot depending on the direction
  if direction == Direction.DOWN then
    sprite.Rotation = 0
    scythe.RenderZOffset = 10
    scythe.Position = Vector(g.p.Position.X, g.p.Position.Y+2*scytheScale)
    --scythe.SpriteOffset = Vector(0,-4)
  elseif direction == Direction.UP then
    sprite.Rotation = 180
    scythe.Position = Vector(g.p.Position.X, g.p.Position.Y-20*scytheScale)
    --scythe.SpriteOffset = Vector(0,-10)
  elseif direction == Direction.LEFT then
    sprite.Rotation = 90
    scythe.Position = Vector(g.p.Position.X-10*scytheScale, g.p.Position.Y-6*scytheScale)
   -- scythe.SpriteOffset = Vector(-10,1)
  elseif direction == Direction.RIGHT then
    sprite.Rotation = -90
    scythe.Position = Vector(g.p.Position.X+10*scytheScale, g.p.Position.Y-6*scytheScale)
    --scythe.SpriteOffset = Vector(10,5)
  end

  --Flipping the scythe when needed (alternating swings)
  if swing == 0 then
    sprite.FlipX = false
  else
    sprite.FlipX = true
    if direction == Direction.RIGHT then
      sprite.Rotation = 90
      --scythe.SpriteOffset = Vector(10,-20)
    elseif direction == Direction.LEFT then
      sprite.Rotation = -90
      --scythe.SpriteOffset = Vector(-10,-17)
    end
  end

  --Scale the scythe
  if scytheScale >= 1.5 then
    scythe.Scale = scytheScale-(scytheScale/2) --Using big scythe sprite
  else
    scythe.Scale = scytheScale --Using small scythe sprite
  end

end

-----------Return the number of tears the player would normally fire
function SamaelMod:getNumTears()
  local numTears = 0 --Count the number of projectiles needed (from multishot items)
  numTears = numTears + 2*g.p:GetCollectibleNum(CollectibleType.COLLECTIBLE_20_20)
  numTears = numTears + 3*g.p:GetCollectibleNum(CollectibleType.COLLECTIBLE_INNER_EYE)
  numTears = numTears + 4*g.p:GetCollectibleNum(CollectibleType.COLLECTIBLE_MUTANT_SPIDER)
  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_THE_WIZ) then
    numTears = numTears+2*g.p:GetCollectibleNum(CollectibleType.COLLECTIBLE_THE_WIZ)
    if numTears % 2 == 1 then --Need an even number with the wiz
      numTears = numTears+1
    end
  end
  return numTears
end

-----------Fire one of samael's unique scythe projectiles-----------
function SamaelMod:fireScytheProjectile(projVel, angle, XOffset, YOffset)
  projVel = projVel:Rotated(angle) --Apply the angle (for multishot and such)
  local pos = Vector(g.p.Position.X + XOffset, g.p.Position.Y + YOffset) --Apply offsets

  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS) then --Fire dr fetus bomb
    g.p:FireBomb(pos, projVel)
  else --Fire scythe projectile
    local proj = g.p:FireTear(pos, projVel, true, false, true) --Fire the tear
    proj = proj:ToTear()
    local var = proj.Variant
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_IPECAC) then
      proj:ChangeVariant(8)
    else
      --Exclude certain special tears(teeth,boogers,etc)
      if var~=2 and var~=26 and var~=27 and var~=28 and var~=30 and var~=31 and
         not g.p:HasCollectible(CollectibleType.COLLECTIBLE_GODHEAD) then

        proj:ChangeVariant(TearVariant.MAGIC_SCYTHE) --Change to custom scythe projectile
      elseif g.p:HasCollectible(CollectibleType.COLLECTIBLE_GODHEAD) then
        proj:SetColor(Color(0,0,0,255,0,0,0), 999,999,false,false)
      else
        proj.Scale = proj.Scale*1.5
      end
      proj.TearFlags = proj.TearFlags | 1 << 1 --Add Piercing
      proj.TearFlags = proj.TearFlags | 1 --Add Spectral
      proj.SpriteScale = Vector(proj.Scale,proj.Scale) --Set proper size
    end
    proj.CollisionDamage = proj.CollisionDamage*scytheProjectileDamageMultiplier --Set new tear damage
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_SAMAEL_CHOCOLATE_MILK) then
      local chocBoost = math.min(charge/chargeTime, 3)
      proj.CollisionDamage = proj.CollisionDamage*chocBoost
      proj.Scale = math.max(proj.Scale, proj.Scale*chocBoost*(2/3))
    end
  end

end

-- Custom deadeye functionality
-- (increases damage every time a scythe swing hits something; bonus is lost when a swing misses
function SamaelMod:deadEyeFunc(interrupt)
  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_SAMAEL_DEAD_EYE) then
    if hits > 0 then
      if deadEyeBoost < properDamage * 2 then
        deadEyeBoost = deadEyeBoost + properDamage * 0.2
        --Add to deadEyeBoost to keep track of how much damage has been added by this effect
        g.p.Damage = g.p.Damage+properDamage*0.2 --Add damage
      end
      deadEyeCountdown = 3
    elseif interrupt then
      deadEyeCountdown = deadEyeCountdown - 1
      if deadEyeCountdown <= 0 then
        g.p.Damage = g.p.Damage - deadEyeBoost --Revert damage to original value
        deadEyeBoost = 0
      end
    else
      g.p.Damage = g.p.Damage - deadEyeBoost --Revert damage to original value
      deadEyeBoost = 0
    end
  end
  hits = 0
end

-------Custom epiphora functionality (increased attack rate for attacking in the same direction repeatedly)-------
function SamaelMod:epiphoraFunc()
  if lastEpiphoraDirection == lastDirection then
    epiphoraCounter = epiphoraCounter + 1 --Add to counter
  else
    epiphoraCounter = 0
  end
  lastEpiphoraDirection = lastDirection
end

-----------Add colours to the scythe, if certain items are collected-----------
function SamaelMod:getScytheColor()
  local color = Color(1, 1, 1, 1, 0, 0, 0)
  local red = {
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_BLOOD_MARTYR),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_CHEMICAL_PEEL),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_BLOOD_CLOT),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_CONTACTS),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_PACT),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_ABADDON),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_TOOTH_PICKS),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_STIGMATA),
  }
  local green = {
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_SCORPIO),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_COMMON_COLD),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_IPECAC),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_SERPENTS_KISS),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_MYSTERIOUS_LIQUID),
  }
  local yellow = {
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_NUMBER_ONE),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_SULFURIC_ACID),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_PERFUME),
  }
  local orange = {
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_FIRE_MIND),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_DEAD_ONION),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_PARASITE),
    g.p:HasCollectible(CollectibleType.COLLECTIBLE_SAMAEL_CHOCOLATE_MILK),
  }
  --local purple = {player:HasCollectible(CollectibleType.COLLECTIBLE_SPOON_BENDER)}
  --local pink = {player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_EYESHADOW)}

  if threeDollarBillEffect == "fire" then table.insert(orange, true) end
  if threeDollarBillEffect == "poison" or threeDollarBillEffect == "creep" then table.insert(green, true) end
  if threeDollarBillEffect == "freeze" then table.insert(red, true) end
  if threeDollarBillEffect == "pee" then table.insert(yellow, true) end

  for i = 1, #red do
    if red[i] then
      color.R = color.R+0.8
    end
  end
  for i = 1, #green do
    if green[i] then
      color.G = color.G+1.5
    end
  end
  for i = 1, #yellow do
    if yellow[i] then
      color.R = color.R+1.5
      color.G = color.G+1.5
    end
  end
  for i = 1, #orange do
    if orange[i] then
      color.R = color.R+2
      color.G = color.G+1
    end
  end
  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_SPOON_BENDER) then
    color.R = color.R+2
    color.B = color.B+2
  end
  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_EYESHADOW) or threeDollarBillEffect == "charm" then
    color.R = color.R+2
    color.B = color.B+1
  end

  --Normalize colour
  local max = math.max(color.R, color.G, color.B)
  local min = math.min(color.R-1, color.G-1, color.B-1)
  color.R = (color.R-min)/(max-min)
  color.G = (color.G-min)/(max-min)
  color.B = (color.B-min)/(max-min)

  --Lighten
  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_SACRED_HEART) then
    color.R = color.R + 0.5
    color.B = color.B + 0.5
    color.G = color.G + 0.5
  --Darken
  elseif g.p:HasCollectible(CollectibleType.COLLECTIBLE_DARK_MATTER) or
         g.p:HasCollectible(CollectibleType.COLLECTIBLE_EVES_MASCARA) or
         threeDollarBillEffect == "fear" then

    color.R = color.R * 0.2
    color.B = color.B * 0.2
    color.G = color.G * 0.2
  --Darken less
  elseif g.p:HasCollectible(CollectibleType.COLLECTIBLE_DEAD_ONION) or
         g.p:HasCollectible(CollectibleType.COLLECTIBLE_SAMAEL_CHOCOLATE_MILK) or
         threeDollarBillEffect == "slow" then

    color.R = color.R * 0.5
    color.B = color.B * 0.5
    color.G = color.G * 0.5
  end

  scytheColor = color
end

-----------Play sound using dummy NPC if needed-----------
function SamaelMod:playSound(ID, volume, pitch)
  g.sfx:Play(ID, volume, 0, false, pitch)
end

-----------On player init (start/continue)-----------
function SamaelMod:PostPlayerInit(player)
  if player:GetPlayerType() ~= samaelID then --If the player is Samael
    return
  end

  -- Add Costumes
  player:AddNullCostume(cloak)
  player:AddNullCostume(hood)
  costumeEquipped = true

  numItems = -1
  swing = 0

  player.FireDelay = 5
  wraithTime = 0
  wraithActive = false
  charge = 0
  wraithCharge = 0 -- Just set it to 0, we don't care about keeping track of it between runs
end

-----------Cache update function for handling charge time and some damage stuff-----------
function SamaelMod:cacheUpdate(player, cacheFlag)
  if player:GetPlayerType() ~= samaelID then
    return
  end

  --Isaac.DebugString("Cache updating for: " .. tostring(cacheFlag))

  SamaelMod:calcChargeTime()
  SamaelMod:getScytheColor()

  --Allow or disable normal firing depending on items
  if player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) or
     player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY) or
     player:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG) or
     player:HasCollectible(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE) or
     (player:HasCollectible(CollectibleType.COLLECTIBLE_TECH_X) and
      not player:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS)) or
     player:HasCollectible(CollectibleType.COLLECTIBLE_CURSED_EYE) or
     player:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS) then

    canShoot = true
  else
    canShoot = false
  end

  if cacheFlag == CacheFlag.CACHE_RANGE then
    if player:HasCollectible(CollectibleType.COLLECTIBLE_SAMAEL_MARKED) then
      player.TearHeight = player.TearHeight - 3.15
    end
  end
  scytheScale = math.max(math.min((player.TearHeight * (-1)) / 23.75, 2), 1)
  if player:HasCollectible(CollectibleType.COLLECTIBLE_PUPULA_DUPLEX) then
    scytheScale = math.max(math.min(scytheScale + 0.33, 2), 1)
  end

  if cacheFlag == CacheFlag.CACHE_DAMAGE then
    player.Damage = player.Damage + 1

    --Increase damage for having certain items (Chemical Peel, Blood Clot, Peircing tears, etc)
    for i = 1, #itemChecks do
      if itemChecks[i] > 0 then
        player.Damage = player.Damage + itemChecks[i]
      end
    end

    --damage boost when Brimstone overrides Dr Fetus
    if player:HasCollectible(CollectibleType.COLLECTIBLE_SAMAEL_DR_FETUS) then
      player.Damage = player.Damage * 1.5
    end

    -- Mom's Knife nerf
    if player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then -- 114
      player.Damage = player.Damage / 1.25
    end

    properDamage = player.Damage --Save proper damage stat
    deadEyeBoost = 0
  end

  if cacheFlag == CacheFlag.CACHE_SPEED then
    if not player:HasCollectible(CollectibleType.COLLECTIBLE_PONY) and -- 130
       not player:HasCollectible(CollectibleType.COLLECTIBLE_WHITE_PONY) then -- 181

      player.MoveSpeed = player.MoveSpeed + 0.15
      --Isaac.DebugString("Decreased speed in the speed cache for Samael: " .. tostring(player.MoveSpeed))
    end
    if wraithActive then
      player.MoveSpeed = player.MoveSpeed + 0.3
      --Isaac.DebugString("Increased speed in the speed cache for Samael (wraithActive): " ..
                          --tostring(player.MoveSpeed))
    end
  end

  if cacheFlag == CacheFlag.CACHE_FIREDELAY then
    if player:HasCollectible(CollectibleType.COLLECTIBLE_SAMAEL_MARKED) then
      player.MaxFireDelay = player.MaxFireDelay - math.ceil(player.MaxFireDelay / 8)
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_TECH_X) and
       not player:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG) then

      fireDelayReduced = true
      fireDelayPenalty = math.min(player.MaxFireDelay*1.5, 30)
    elseif player:HasCollectible(CollectibleType.COLLECTIBLE_TECH_X) and
           player:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG) then

      fireDelayReduced = false
    elseif player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
      fireDelayReduced = true
      fireDelayPenalty = math.min(player.MaxFireDelay*0.75, 25)
    else
      fireDelayReduced = false
    end
    if fireDelayReduced then player.MaxFireDelay = math.ceil(player.MaxFireDelay+fireDelayPenalty) end
  end

  if player:HasCollectible(442) then -- Dark Princes Crown
    if player:GetHearts() == 2 and cacheFlag == CacheFlag.CACHE_FIREDELAY then
      player.MaxFireDelay = math.ceil(player.MaxFireDelay*0.666)
    end
    player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
  end
  if player:HasCollectible(CollectibleType.COLLECTIBLE_DARK_PRINCESS_CROWN) and -- 442
     player:GetHearts() == 2 and
     cacheFlag == CacheFlag.CACHE_DAMAGE then

    player.Damage = player.Damage*1.666
  end
end

-----------Calculate # of frames needed to charge up a projectile-----------
function SamaelMod:calcChargeTime()
  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_SOY_MILK) and
     not g.p:HasCollectible(CollectibleType.COLLECTIBLE_LIBRA) then

    chargeTime = 1
    return
  end
  if g.p.MaxFireDelay < chargeTimeMax then --Calculate charge time (Parabola! Because why not)
    local x = g.p.MaxFireDelay
    local min = chargeTimeMin
    local mid = chargeTimeMid
    local max = chargeTimeMax
    --Using formulas to fit a parabola to three points
    local a = (mid*max - min*(max-10) - max*10)/((-1)*max*max*10+100*max)
    local b = (mid-min-a*(100))/10
    --local c = min
    chargeTime = math.floor(a*x*x + b*x + min) -- y = ax^2 + bx + c
  else
    chargeTime = chargeTimeMax --Cap chargetime
  end
end

-----------Calculate delay between scythe swings-----------
function SamaelMod:calcSwingDelay()
  local delay = g.p.MaxFireDelay
  --Negate certain tears down effects for melee swings
  if fireDelayReduced then
    delay = delay-fireDelayPenalty
  end
  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_INNER_EYE) or
     g.p:HasCollectible(CollectibleType.COLLECTIBLE_MUTANT_SPIDER) then

    delay = (delay-3)/2.1
  end
  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) and
     not g.p:HasCollectible(CollectibleType.COLLECTIBLE_TECH_X) then

    delay = delay/3
  elseif g.p:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG) and
         not g.p:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY) and
         not g.p:HasCollectible(CollectibleType.COLLECTIBLE_TECH_X) then

    delay = delay/4
  elseif g.p:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG) and
         g.p:HasCollectible(CollectibleType.COLLECTIBLE_TECH_X) then

    delay = delay/3
  elseif g.p:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS) then
    delay = delay/2.5
  end

  if delay > swingDelayCap then --Cap the swing delay
    delay = swingDelayCap
  end
  if wraithActive and wraithCooldown == 0 then --Swing delay is halved in wraith mode
    delay = delay*0.5
  end
  if threeDollarBillEffect == "pee" then
    delay = delay*0.5
  end

  for i = 1, math.min(epiphoraCounter, 8) do
    delay = delay - delay*(1/16)
  end

  delay = math.floor(delay)
  if delay < 1 then delay = 1 end

  return delay
end

-----------Callback function for the Scythe's hitbox (Its an invisible sacrificial dagger)-----------
function SamaelMod:hitBoxFunc(hitBox)
  -- Local variables
  local character = g.p:GetPlayerType()

  if hitBox.Variant ~= FamiliarVariant.SACRIFICIAL_DAGGER or
     hitBox.SubType ~= hitBoxType then --If its the right entity

    return
  end

  if hitBox.Parent == nil or
     character ~= samaelID or
     dying then

    hitBox:Remove()
    return
   end

  hitBox.Size = 40 * scytheScale

  --Put it in the correct position, depending on the direction passed to it
  if hitBox.Coins == Direction.UP then
    hitBox.Position = Vector(g.p.Position.X, g.p.Position.Y - 45 * scytheScale)
  elseif hitBox.Coins == Direction.DOWN then
    hitBox.Position = Vector(g.p.Position.X, g.p.Position.Y + 35 * scytheScale)
  elseif hitBox.Coins == Direction.LEFT then
    hitBox.Position = Vector(g.p.Position.X - 40 * scytheScale, g.p.Position.Y)
  elseif hitBox.Coins == Direction.RIGHT then
    hitBox.Position = Vector(g.p.Position.X + 40 * scytheScale, g.p.Position.Y)
  else --If direction is -1, go offscreen
    hitBox.Position = g.zeroVector
  end

  hitBox.Velocity = g.zeroVector

  --Destroy poop
  if hitBox.Coins ~= -1 then
    local index = g.r:GetGridIndex(hitBox.Position) --Get grid index of hitBox's position
    local indexes = { --Array of that index and adjacent tiles
      index, index+1, index-1, index + g.r:GetGridWidth(), index - g.r:GetGridWidth(),
    }
    for i = 1, 5 do
      if g.p:HasCollectible(CollectibleType.COLLECTIBLE_SULFURIC_ACID) then
        g.r:DestroyGrid(indexes[i], 1) --Destroy rocks and poop on these tiles if the player has sulfuric acid
      else
        g.r:DamageGrid(indexes[i], 1) --Damage poop in any of these tiles
      end
    end
  end
end

-----------Damage callback for the player taking damage-----------
function SamaelMod:playerDamage(tookDamage, damage, damageFlags, damageSourceRef)
  --Resist all damage in wraith mode except for things like the IV bag or Razor
  if wraithActive and (damageFlags & DamageFlag.DAMAGE_RED_HEARTS) == 0 then
    return false
  end
end

-----------Damage callback for scythe hits/scythe projectiles-----------
function SamaelMod:scytheHits(tookDamage, damage, damageFlags, damageSourceRef)
  -- Local variables
  local gameFrameCount = g.g:GetFrameCount()
  local isaacFrameCount = Isaac.GetFrameCount()

  if ((damageSourceRef ~= nil and damageSourceRef.Entity ~= nil) or
      (damageSourceRef.Entity == nil and (damageFlags & DamageFlag.DAMAGE_LASER) ~= 0)) and
     g.p:GetPlayerType() == samaelID and
     tookDamage.Type ~= EntityType.ENTITY_PLAYER then

    local damageSource
    if damageSourceRef.Entity ~= nil then
      damageSource = damageSourceRef.Entity
    else
      damageSource = g.p
    end
    local damType = damageSource.Type

    --New Wraith meter charging code
    if damType == EntityType.ENTITY_FAMILIAR or
       damType == EntityType.ENTITY_KNIFE or
       damType == EntityType.ENTITY_TEAR or
       damType == EntityType.ENTITY_PLAYER and
       tookDamage:IsVulnerableEnemy() and
       lastFrameWraithCharge == wraithCharge then

      if wraithChargeCooldown == 0 then
        if damType == EntityType.ENTITY_FAMILIAR and
           damageSource.Variant == FamiliarVariant.SACRIFICIAL_DAGGER and
           damageSource.SubType == hitBoxType then

          local addCharge = math.min(g.p.MaxFireDelay * 0.2, 20)
          wraithCharge = wraithCharge + addCharge
          --Isaac.DebugString("Added wraithCharge from #1: " .. tostring(addCharge))
        else
          local addCharge = math.min(math.max(g.p.MaxFireDelay, 1), 20)
          wraithCharge = wraithCharge + addCharge
          --Isaac.DebugString("Added wraithCharge from #2: " .. tostring(addCharge))
        end
        wraithChargeCooldown = g.p.MaxFireDelay
        wraithChargePenalty = 3
      else
        local addCharge = math.min(damage, 20) / wraithChargePenalty
        wraithCharge = wraithCharge + addCharge
        wraithChargePenalty = wraithChargePenalty + 2
        --Isaac.DebugString("Added wraithCharge from #3 damage: " .. tostring(addCharge))
      end
    end
    if damType == EntityType.ENTITY_FAMILIAR and
       damageSource.Variant == FamiliarVariant.SACRIFICIAL_DAGGER and
       damageSource.SubType == hitBoxType and tookDamage:IsVulnerableEnemy() then

      --damageSource = damageSource:ToFamiliar()
      tookDamage = tookDamage:ToNPC()
      --local sprite = damageSource.Parent:GetSprite()
      Isaac.Spawn(1000, 2, 0, tookDamage.Position, g.zeroVector, tookDamage) --Blood effect
      tookDamage:PlaySound(77, 0.75, 0, false, 1.8) --Play hit sound

      --Get knockback bonus from items
      local knockBackBonus = 0
      if g.p:HasCollectible(CollectibleType.COLLECTIBLE_PISCES) then
        knockBackBonus = knockBackBonus + 1.5
      end
      if g.p:HasCollectible(CollectibleType.COLLECTIBLE_8_INCH_NAILS) then
        knockBackBonus = knockBackBonus + 1.5
      end
      if g.p:HasTrinket(TrinketType.TRINKET_BLISTER) then
        knockBackBonus = knockBackBonus + 1.5
      end
       --"Push" the enemy away from the player (knockback)
       local vel = tookDamage.Position:__sub(g.p.Position):Normalized():__mul(knockbackMagnitude+knockBackBonus)
      tookDamage:AddVelocity(vel)

      --Status condition stuff
      math.randomseed(isaacFrameCount + gameFrameCount)
      local luck = math.floor(g.p.Luck)
      if luck < 1 then luck = 1
      elseif luck > luckCap then luck = luckCap end

      if threeDollarBillEffect == "fire" or fruitCakeEffect == "fire" or (g.p.TearFlags & 1 << 22) ~= 0 then --Burn
        tookDamage:AddBurn(damageSourceRef, 80, 5)
      end
      if fruitCakeEffect == "poison" or
         threeDollarBillEffect == "poison" or
         (g.p.TearFlags & 1 << 4) ~= 0 or
         (g.p.TearFlags & 1 << 12) ~= 0 or
         ((g.p:HasCollectible(103) or
           g.p:HasCollectible(393)) and
          math.random(luckCap+1-luck) == 1) then --Poison

        tookDamage:AddPoison(damageSourceRef, 80, 5)
      end
      if fruitCakeEffect == "slow" or
         (g.p.TearFlags & 1 << 3) ~= 0 or
         ((g.p:HasCollectible(231) or
           g.p:HasCollectible(89) or
           threeDollarBillEffect == "slow") and
          math.random(luckCap+1-luck) == 1) then --Slow

        tookDamage:AddSlowing(damageSourceRef, 125, 2, Color(0.3,0.3,0.3,1,0,0,0))
      end
      if fruitCakeEffect == "freeze" or
         (g.p.TearFlags & 1 << 5) ~= 0 or
         ((g.p:HasCollectible(110) or
           threeDollarBillEffect == "freeze") and
          math.random(luckCap+1-luck) == 1) then --Freeze

        tookDamage:AddFreeze(damageSourceRef, 80)
      end
      if fruitCakeEffect == "charm" or
         (g.p.TearFlags & 1 << 13) ~= 0 or
         ((g.p:HasCollectible(200) or threeDollarBillEffect == "charm") and
         math.random(luckCap+1-luck) == 1) then --Charm

        tookDamage:AddCharmed(80)
      end
      if fruitCakeEffect == "confuse" or
         (g.p.TearFlags & 1 << 14) ~= 0 or
         ((g.p:HasCollectible(201) or
           threeDollarBillEffect == "confuse") and
          math.random(luckCap+1-luck) == 1) then --Confuse

        tookDamage:AddConfusion(damageSourceRef, 80, false)
      end
      if fruitCakeEffect == "shrink" or
         (g.p.TearFlags & 1 << 41) ~= 0 or
         (g.p:HasCollectible(398) and math.random(luckCap+1-luck) == 1) then --Shrink

        tookDamage:AddShrink(damageSourceRef, 80)
      end
      if fruitCakeEffect == "fear" or
         (g.p.TearFlags & 1 << 20) ~= 0 or
         ((g.p:HasCollectible(228) or
           g.p:HasCollectible(230) or
           g.p:HasCollectible(259) or
           threeDollarBillEffect == "fear") and
          math.random(luckCap+1-luck) == 1) then --Fear

        tookDamage:AddFear(damageSourceRef, 80)
      end
      if (fruitCakeEffect == "greed" or
          g.p:HasCollectible(CollectibleType.COLLECTIBLE_EYE_OF_GREED)) and
         math.random(luckCap+1-luck) == 1 then --Eye of Greed

        tookDamage:AddMidasFreeze(damageSourceRef, 80)
      end

      if (fruitCakeEffect == "light" and math.random(2)==1) or
         (math.random(luckCap+1-luck)==1 and
          g.p:HasCollectible(CollectibleType.COLLECTIBLE_HOLY_LIGHT)) then --Holy Light

        Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.CRACK_THE_SKY, 0,
                    Isaac.GetFreeNearPosition(tookDamage.Position, tookDamage.Size), g.zeroVector, g.p)
      end
      if (threeDollarBillEffect == "creep" or
          fruitCakeEffect == "creep" or
          g.p:HasCollectible(CollectibleType.COLLECTIBLE_MYSTERIOUS_LIQUID)) and
         math.random(2) == 1 then --Mysterious Liquid

        Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.PLAYER_CREEP_GREEN, 0,
                    Isaac.GetFreeNearPosition(tookDamage.Position, tookDamage.Size), g.zeroVector, g.p)
      end
      if (fruitCakeEffect == "keeper" or
          g.p:HasCollectible(CollectibleType.COLLECTIBLE_HEAD_OF_THE_KEEPER)) and
          math.random(luckCap+1-luck) == 1 then --Head of the Keepo

        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COIN, CoinSubType.COIN_PENNY,
                    Isaac.GetFreeNearPosition(tookDamage.Position, tookDamage.Size), g.zeroVector, nil)
      end

      --Flies and spiders (guppy, mulligan, parisitoid)
      if g.p:HasPlayerForm(PlayerForm.PLAYERFORM_GUPPY) then
        g.p:AddBlueFlies(1, g.p.Position, tookDamage)
      elseif g.p:HasCollectible(CollectibleType.COLLECTIBLE_MULLIGAN) and math.random(6) == 1 then
        g.p:AddBlueFlies(1, g.p.Position, tookDamage)
      end
      if fruitCakeEffect == "fly" or
         (g.p:HasCollectible(CollectibleType.COLLECTIBLE_PARASITOID) and math.random(luckCap+1-luck) == 1) then
        if math.random(2) == 1 then
          g.p:AddBlueSpider(g.p.Position)
        else
          g.p:AddBlueFlies(1, g.p.Position, tookDamage)
        end
      end

      --Euthanasia
      if g.p:HasCollectible(CollectibleType.COLLECTIBLE_EUTHANASIA) and
         not tookDamage:IsBoss() and math.random(luckCap+1-luck) == 1 then

        local s = 10
        local directions = {
          Vector(-s, -s),
          Vector(-s, s),
          Vector(s, -s),
          Vector(s, s),
          Vector(0,-s*1.5),
          Vector(-s*1.5, 0),
          Vector(s*1.5, 0),
          Vector(0, s*1.5),
        }
        for i = 1, #directions do
          local needleTear = g.p:FireTear(tookDamage.Position, directions[i], false, true, false)
          needleTear:ChangeVariant(TearVariant.NEEDLE)
        end
        tookDamage:Kill()
      end

      --Little Horn
      if g.p:HasCollectible(CollectibleType.COLLECTIBLE_LITTLE_HORN) and
         not tookDamage:IsBoss() and math.random(luckCap+1-luck) == 1 then

        tookDamage:Kill()
      end

      local parasiteTear = 0
      --Split tears
      if g.p:HasCollectible(CollectibleType.COLLECTIBLE_PARASITE) or
         g.p:HasCollectible(CollectibleType.COLLECTIBLE_CRICKETS_BODY) or
         g.p:HasCollectible(CollectibleType.COLLECTIBLE_COMPOUND_FRACTURE) then

        if not parasiteTriggered then
          parasiteTear = g.p:FireTear(tookDamage.Position, Vector(8,0):Rotated(math.random(360)),
                                         false, true, true):ToTear() --Fire the tear
          parasiteTear.CollisionDamage = parasiteTear.CollisionDamage*0.5
          parasiteTear.Scale = 0.66
          parasiteTear.Mass = 0
          parasiteTear.TearFlags = parasiteTear.TearFlags | 1 << 1 --Add piercing
          parasiteTriggered = true
        else
          parasiteTriggered = false
        end
      end
      --Jacob's ladder
      if (g.p:HasCollectible(CollectibleType.COLLECTIBLE_JACOBS_LADDER) and
          (parasiteTear == 0 or fruitCakeEffect == "shock")) or
         fruitCakeEffect == "shock" then

        if not jacobTriggered then
          local jacobTear = g.p:FireTear(tookDamage.Position, g.zeroVector:Rotated(math.random(360)),
                                         false, true, true):ToTear() --Fire the tear
          jacobTear.TearFlags = 1 << 53 --Add piercing
          jacobTear.CollisionDamage = 0.0
          jacobTear.Mass = 0
          jacobTear.Visible = false
          jacobTear:SetColor(zeroColor, 999, 999, false, false)
          jacobTriggered = true
        else
          jacobTriggered = false
        end
      end

      hits = hits + 1
    elseif damageSource.Type == EntityType.ENTITY_FAMILIAR and tookDamage:IsVulnerableEnemy() then
      local addCharge = math.max(math.min(damage, tookDamage.HitPoints) * 0.33, 1)
      if addCharge > 20 then
        addCharge = 20
      end
      wraithCharge = wraithCharge + addCharge
      --Isaac.DebugString("Added wraithCharge from #4: " .. tostring(addCharge))
    end
    if wraithCharge > 100 then
      wraithCharge = 100
    end
  end
end

-----------Special animation effects-----------
function SamaelMod:specialAnimFunc(npc)
  local sprite = npc:GetSprite()
   --Trigger the blood splatter effect for death animation
  if sprite:IsPlaying("Death") and
     sprite:IsEventTriggered("Blood") then

    Isaac.Spawn(1000, 77, 0, npc.Position, g.zeroVector, npc)
    npc:PlaySound(28, 1, 0, false, 1)
    npc:MakeSplat(5.0)
  elseif sprite:IsPlaying("WraithDown") or
         sprite:IsPlaying("WraithUp") or
         sprite:IsPlaying("WraithLeft") or
         sprite:IsPlaying("WraithRight") then --Wraith mode

    if not wraithActive or wraithCooldown > 0 or g.p:GetSprite():IsPlaying("Trapdoor") then
      npc:Remove()
      return
    end
    npc.Position = g.p.Position
    npc.Velocity = g.p.Velocity
    local dir = g.p:GetHeadDirection()
    if not sprite:IsPlaying("WraithDown") and (dir == Direction.DOWN or dir == Direction.NO_DIRECTION) then
      sprite:Play("WraithDown", 1)
    elseif not sprite:IsPlaying("WraithUp") and dir == Direction.UP then
      sprite:Play("WraithUp", 1)
    elseif not sprite:IsPlaying("WraithLeft") and dir == Direction.LEFT then
      sprite:Play("WraithLeft", 1)
    elseif not sprite:IsPlaying("WraithRight") and dir == Direction.RIGHT then
      sprite:Play("WraithRight", 1)
    end
  end
end

------The only function that loops through every entity in the room.
------I tried to limit this mod to only do this once per update------
function SamaelMod:roomEntitiesLoop()
  if g.p:GetPlayerType() ~= samaelID then
    return
  end

  for _, entity in ipairs(Isaac.GetRoomEntities()) do
    if (entity.Type == EntityType.ENTITY_FIREPLACE or
        entity.Type == EntityType.ENTITY_MOVABLE_TNT) and hitPos ~= nil then

      --Break fireplaces with scythe
      if entity.Position:Distance(hitPos) <= 55*scytheScale then
        entity:TakeDamage(g.p.Damage, 0, EntityRef(g.p), 5)
      end

    elseif entity.Type == EntityType.ENTITY_LASER then
      --custom techX stuff
      if entity.Parent == nil then
        entity:Remove()
      elseif entity.Parent.Type == EntityType.ENTITY_SAMAEL_SCYTHE then
        if scytheState ~= 2 then
          entity:Remove()
        else
          entity.Position = g.p.Position
          entity.Velocity = g.p.Velocity
        end
      elseif entity.Parent.Type == EntityType.ENTITY_BOMBDROP then
        entity.Position = entity.Parent.Position
        entity.Velocity = entity.Parent.Velocity
      end

    elseif entity.Type == EntityType.ENTITY_TEAR and
           entity.Variant == TearVariant.MAGIC_SCYTHE and
           not g.p:HasCollectible(CollectibleType.COLLECTIBLE_GODHEAD) then

      --Keep the size of the scythe projectiles consistent whenever it might change (proptosis, lump of coal, etc)
      entity = entity:ToTear()
      entity.SpriteScale = Vector(entity.Scale, entity.Scale)

    elseif entity.Type == EntityType.ENTITY_TEAR  then
      entity = entity:ToTear()
      local sprite = entity:GetSprite()
      if (entity.TearFlags & 1 << 55) ~= 0 and sprite:GetFilename() ~= "gfx/samael_scythe_projectile.anm2" then
        --entity:ChangeVariant(8)
        sprite:Load("gfx/samael_scythe_projectile.anm2", true)
        sprite:Play("Idle", true)
        entity.SpriteScale = Vector(entity.Scale*0.75, entity.Scale*0.75)
      end
    elseif entity.Type == EntityType.ENTITY_KNIFE and
           (entity.SubType == 0 or entity.SubType == 1) and
           (entity.Parent.Type == EntityType.ENTITY_PLAYER or
            entity.Parent.Type == EntityType.ENTITY_KNIFE) then

      --Handling knives
      SamaelMod:knifeUpdate(entity:ToKnife())

    elseif entity.Type == EntityType.ENTITY_KNIFE and
           not entity.Parent.Parent == nil and
           entity.Parent.Parent.Type == EntityType.ENTITY_PLAYER and
           entity.Variant ~= 617 then

      entity = entity:ToKnife()
      entity:GetSprite():Load("gfx/samael_scythe_knife.anm2", true)
      entity:GetSprite():Play("Hidden", true)
      entity.Variant = 617
      if hideScythe then
        entity.SizeMulti = Vector(4*scytheScale,4*scytheScale)
        entity.SpriteScale = Vector(scytheScale,scytheScale)
      else
        entity.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
      end
    end
  end
end

-----------Readd costumes after rerolling-----------
function SamaelMod:postReroll()
  local character = g.p:GetPlayerType()
  if character == samaelID then
    g.p:AddNullCostume(cloak)
    g.p:AddNullCostume(hood)
  end
end

-----------Wraith Skull item-----------
function SamaelMod:activateWraith()
  wraithActivationCooldown = 280

  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_HOLY_LIGHT) then
    g.p:UseActiveItem(CollectibleType.COLLECTIBLE_CRACK_THE_SKY, false, false, false, false)
  end
  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_CURSE_OF_THE_TOWER) then
    g.p:UseActiveItem(CollectibleType.COLLECTIBLE_ANARCHIST_COOKBOOK, false, false, false, false)
  end
  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_VARICOSE_VEINS) then
    g.p:UseActiveItem(CollectibleType.COLLECTIBLE_TAMMYS_HEAD, false, false, false, false)
  end
  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_ATHAME) or
     g.p:HasCollectible(CollectibleType.COLLECTIBLE_MAW_OF_VOID) then

    g.p:SpawnMawOfVoid(100)
  end

  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_BLACK_POWDER) then
    local pentagram = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.PENTAGRAM_BLACKPOWDER, 0,
                                  g.p.Position, g.zeroVector, g.p):ToEffect()
    pentagram.State = 1
    pentagram.Size = 150
    pentagram.SpriteScale = Vector(0.75,0.75)
  end

  wraithActive = true
  wraithCharge = 0
  wraithTime = 100
  g.p.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
  SamaelMod:playSound(33, 1, 1.1)
  g.p.MoveSpeed = g.p.MoveSpeed + 0.3
  --Isaac.DebugString("Increased speed from the Wraith ability being activated: " .. tostring(g.p.MoveSpeed))

  --Black poof effect
  local poof = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF02, 0,
                           g.p.Position, g.zeroVector, g.p):ToEffect()
  poof:GetSprite().Color = Color(0, 0, 0, 0.66, 0, 0, 0)
  poof:FollowParent(g.p)

  --Special animation
  g.p:GetSprite().Color = zeroColor
  local special = Isaac.Spawn(EntityType.ENTITY_SAMAEL_SPECIAL_ANIMATIONS, 0, 0,
                              g.p.Position, g.zeroVector, g.p):ToNPC() --Spawn the special animations entity
  special:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
  special:GetSprite():Play("WraithDown", 1) --Wraith form animation
  special:GetSprite().Color = Color(0.75,0.25,0.25,0.8,0,0,0)
  special.CanShutDoors = false
  special.Scale = g.p.SpriteScale.X
end

-----------Replacing knives with scythes-----------
function SamaelMod:knifeUpdate(knife)
  local sprite = knife:GetSprite()

  if sprite:GetFilename() ~= "gfx/samael_scythe_knife.anm2" then --Replace the sprite
    sprite:Load("gfx/samael_scythe_knife.anm2", true)
    if scytheScale >= 1.5 then
      sprite:Play("Big", true)
    else
      sprite:Play("Idle", true)
    end
    knife.Variant = 617
    knife.SizeMulti = Vector(4, 4)
  end

  if knife.Variant == 617 and knife.SubType == 0 then
    --knife.SizeMulti = Vector(4 * scytheScale, 4 * scytheScale)
    knife.SizeMulti = Vector(1.5 * scytheScale, 1.5 * scytheScale)
    if scytheScale >= 1.5 then
      local X = scytheScale - (scytheScale / 2)
      X = X / 1.25
      local Y = scytheScale - (scytheScale / 2)
      Y = Y / 1.25
      knife.SpriteScale = Vector(X, Y)
    else
      --knife.SpriteScale = Vector(scytheScale, scytheScale)
      knife.SpriteScale = Vector(scytheScale / 1.25, scytheScale / 1.25)
    end

    if not g.p:HasCollectible(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE) then
      --Only enable the knife-scythe when thrown (requires charging for at least 5 frames)
      if (knife:IsFlying() or knife.Parent.Type == EntityType.ENTITY_KNIFE) and
         not (sprite:IsPlaying("Idle") or sprite:IsPlaying("Big")) and
         lastCharge > 5 then

        knife.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ENEMIES
        if scytheScale >= 1.5 then
          sprite:Play("Big", true)
        else
          sprite:Play("Idle", true)
        end
        hideScythe = true

      elseif not (knife:IsFlying() or knife.Parent.Type == EntityType.ENTITY_KNIFE) and
             (sprite:IsPlaying("Idle") or sprite:IsPlaying("Big")) then

        --Hide and disable the knife-scythe when not thrown
        sprite:SetFrame("Hidden", 0)
        knife.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        hideScythe = false
      end
    end
    scytheColor = sprite.Color
  end

  -- This fixes the bug where if you have Mom's Knife on Samael and respawn as another character,
  -- the knife will be be gone and you won't be able to shoot tears and the game will softlock
  if dying then
    knife:Remove()
  end
end

function SamaelMod:PostGameStartedReset()
  -- Local variables
  local character = g.p:GetPlayerType()

  SamaelMod.SacDaggerAcquired = false

  wraithActive = false
  wraithCooldown = 0
  wraithTime = 0
  wraithCharge = 0
  scytheAnimationEndFrame = 0

  numItems = -1
  itemChecks = {}

  if character == samaelID then
    g.p:AddCacheFlags(CacheFlag.CACHE_ALL) -- 0xFFFFFFFF
    g.p:EvaluateItems()
  end

  --Isaac.DebugString("Cleared all Samael variables.")
end

function SamaelMod:PostUpdateFixBugs()
  -- Local variables
  local character = g.p:GetPlayerType()

  -- Judas Shadow + Wraith Skull bug
  if character ~= samaelID then
    if g.p:HasCollectible(CollectibleType.COLLECTIBLE_WRAITH_SKULL) then
      g.p:RemoveCollectible(CollectibleType.COLLECTIBLE_WRAITH_SKULL)
      Isaac.DebugString("Removed the Wraith Skull since we are not on Samael anymore.")
    end
    if g.run.schoolbag.item == CollectibleType.COLLECTIBLE_WRAITH_SKULL then
      g.run.schoolbag.item = 0
      Schoolbag.sprites.item = nil
      Isaac.DebugString("Removed the Wraith Skull (from the Schoolbag) since we are not on Samael anymore.")
    end

    return
  end

  -- Sacrificial Dagger bug
  if not SamaelMod.SacDaggerAcquired and
     g.p:HasCollectible(CollectibleType.COLLECTIBLE_SACRIFICIAL_DAGGER) then -- 172

    SamaelMod.SacDaggerAcquired = true

    -- Check for an existing Sacrifical Dagger
    local foundSacDag = false
    local daggers = Isaac.FindByType(EntityType.ENTITY_FAMILIAR, -- 3
                                     FamiliarVariant.SACRIFICIAL_DAGGER, -1, false, false) -- 35
    for i, dagger in ipairs(daggers) do
      if dagger.SubType ~= hitBoxType then
        foundSacDag = true
        Isaac.DebugString("Found Sacrificial Dagger familiar entity: " .. tostring(dagger.Index))
      end
    end
    if not foundSacDag then
      -- Manually spawn a Sacrificial Dagger familiar (3.35)
      g.g:Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.SACRIFICIAL_DAGGER,
                g.p.Position, g.zeroVector, g.p, 0, 0)
      Isaac.DebugString("Spawned a new Sac Dagger familiar.")
    end
  end
end

-- Called from the "CheckEntities:NonGrid()" and "SamaelMod:CheckHairpin()" functions
function SamaelMod:CheckRechargeWraithSkull()
  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_WRAITH_SKULL) and
     wraithCharge ~= 100 then

    wraithCharge = 100
    Isaac.DebugString("Manually charged the Wraith Skull (from Lil' Battery / Charged Key / Hairpin).")
  end
end

-- Called from the "PostNewRoom:NewRoom2()" function
function SamaelMod:CheckHairpin()
  -- Local variables
  local roomType = g.r:GetType()

  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_WRAITH_SKULL) and
     -- We don't want to check for "player:NeedsCharge()" because the Hairpin will actually work,
     -- but if the wraithCharge variable is not updated, then it will get uncharged on the next frame
     g.p:HasTrinket(TrinketType.TRINKET_HAIRPIN) and -- 120
     roomType == RoomType.ROOM_BOSS and -- 5
     g.l:GetCurrentRoomDesc().VisitedCount == 1 then

    Isaac.DebugString("Hairpin recharge detected.")
    SamaelMod:CheckRechargeWraithSkull()
  end
end

-- Fix the bug where Samael's head will jerk violently when the player spams the tear shoot keys (1/2)
function SamaelMod:IsActionPressed()
  -- Local variables
  local gameFrameCount = g.g:GetFrameCount()
  local character = g.p:GetPlayerType()

  if character ~= samaelID then
    return
  end

  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) or -- 118
     g.p:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS) or -- 168
     g.p:HasCollectible(CollectibleType.COLLECTIBLE_CURSED_EYE) or -- 316
     g.p:HasCollectible(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE) then -- 329

    return
  end

  if scytheAnimationEndFrame == 0 then
    return
  end

  if gameFrameCount >= scytheAnimationEndFrame or -- We have reached the end of the scythe swing animation
     swingDelay <= 1 then -- The scythe swing animation has not finished, but we are ready to swing again

    scytheAnimationEndFrame = 0
    return
  end

  -- Just return true for every button action so that the button will be held down;
  -- we control the actual direction in the "SamaelMod:GetActionValue()" function
  -- (this part is necessary or the player will not actually shoot any tears)
  return true
end

-- Fix the bug where Samael's head will jerk violently when the player spams the tear shoot keys (2/2)
function SamaelMod:GetActionValue(buttonAction)
  -- Local variables
  local gameFrameCount = g.g:GetFrameCount()
  local character = g.p:GetPlayerType()

  if character ~= samaelID then
    return
  end

  if g.p:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) or -- 118
     g.p:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS) or -- 168
     g.p:HasCollectible(CollectibleType.COLLECTIBLE_CURSED_EYE) then -- 316

    return
  end

  if scytheAnimationEndFrame == 0 then
    return
  end

  if gameFrameCount >= scytheAnimationEndFrame or -- We have reached the end of the scythe swing animation
     swingDelay <= 1 then -- The scythe swing animation has not finished, but we are ready to swing again

    scytheAnimationEndFrame = 0
    return
  end

  -- We need to tell the game which direction we want to shoot in
  if (buttonAction == ButtonAction.ACTION_SHOOTLEFT and -- 5
      lastDirection == Direction.LEFT) or -- 0
     (buttonAction == ButtonAction.ACTION_SHOOTRIGHT and -- 4
      lastDirection == Direction.RIGHT) or -- 2
     (buttonAction == ButtonAction.ACTION_SHOOTUP and -- 6
      lastDirection == Direction.UP) or -- 1
     (buttonAction == ButtonAction.ACTION_SHOOTDOWN and -- 7
      lastDirection == Direction.DOWN) then -- 3

    return 1
  end

  return 0
end

return SamaelMod
