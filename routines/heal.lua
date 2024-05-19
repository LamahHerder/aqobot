local mq = require('mq')
local config = require('interface.configuration')
local logger = require('utils.logger')
local timer = require('libaqo.timer')
local abilities = require('ability')
local state = require('state')

local healing = {}

function healing.init() end

local HEAL_TYPES = {
    GROUP='group',
    GROUPPANIC='grouppanic',
    HOT='hot',
    PANIC='panic',
    REGULAR='regular',
    TANK='tank',
    GROUPHOT='grouphot',
}

local tankClasses = {WAR=true,PAL=true,SHD=true}
local melees = {MNK=true,BER=true,ROG=true,BST=true,WAR=true,PAL=true,SHD=true,RNG=true}
local hottimers = {}
local reztimer = timer:new(30000)

local function healEnabled(options, key)
    return options[key] == nil or options[key].value
end

--[[
    1. Determine who to heal:
        a. self very hurt -- self,panic
        b. tank very hurt -- tank,panic
        c. other very hurt -- other,panic
        d. multiple hurt -- group
        e. self hurt -- self,regular
        f. tank hurt -- tank,regular
        g. other hurt -- other,regular
        h. melee hot
        i. xtargets
    2. Determine heal to use
        a. panic
        b. group
        c. regular
]]
-- returns:
-- me.ID, 'panic'
-- me.ID, 'regular'
-- tank.ID, 'panic'
-- member.ID, 'regular'
-- 'group', 'regular'
local function getHurt(options)
    local numHurt = 0
    local mostHurtName = nil
    local mostHurtID = 0
    local mostHurtPct = 100
    local mostHurtClass = nil
    local mostHurtDistance = 300
    local mostHurtPetName = nil
    local mostHurtPetID = 0
    local mostHurtPetPct = 100
    local mostHurtPetDistance = 300
    local myHP = mq.TLO.Me.PctHPs()
    if myHP < config.get('PANICHEALPCT') then
        return mq.TLO.Me.ID(), HEAL_TYPES.PANIC, true
    elseif myHP < config.get('HOTHEALPCT') then
        mostHurtName = mq.TLO.Me.CleanName()
        mostHurtID = mq.TLO.Me.ID()
        mostHurtPct = myHP
        mostHurtClass = mq.TLO.Me.Class.ShortName()
        mostHurtDistance = 0
        logger.debug(logger.flags.routines.heal, 'i need healing')
        if myHP < config.get('HEALPCT') then numHurt = numHurt + 1 end
    end
    local tank
    if mq.TLO.Group.MainTank() then
        tank = mq.TLO.Group.MainTank
    elseif state.actorTankID then
        tank = mq.TLO.Spawn(('id %s'):format(state.actorTankID))
    end
    if (not tank or not tank()) and config.get('PRIORITYTARGET'):len() > 0 then
        tank = mq.TLO.Spawn('='..config.get('PRIORITYTARGET'))
    end
    if tank and tank() and not tank.Dead() then
        local tankHP = tank.PctHPs() or 100
        local distance = tank.Distance3D() or 300
        if tankHP < config.get('PANICHEALPCT') and distance < 200 then return tank.ID(), HEAL_TYPES.PANIC, mq.TLO.Group.Member(tank.CleanName())() ~= nil end
    end
    if healEnabled(options, 'HEALPET') and mq.TLO.Pet.ID() > 0 then
        local memberPetHP = mq.TLO.Pet.PctHPs() or 100
        local memberPetDistance = mq.TLO.Pet.Distance3D() or 300
        if memberPetHP < 60 and memberPetDistance < 200 then
            mostHurtPetName = mq.TLO.Pet.CleanName()
            mostHurtPetID = mq.TLO.Pet.ID()
            mostHurtPetPct = memberPetHP
            mostHurtPetDistance = memberPetDistance
        end
    end
    local groupSize = mq.TLO.Group.GroupSize()
    if groupSize then
        if (mq.TLO.Group.Injured(config.get('PANICHEALPCT'))() or 0) >= config.get('GROUPHEALMIN') then
            return nil, HEAL_TYPES.GROUPPANIC, true
        elseif (mq.TLO.Group.Injured(config.get('GROUPHEALPCT'))() or 0) >= config.get('GROUPHEALMIN') then
            return nil, HEAL_TYPES.GROUP, true
        end
        for i=1,groupSize-1 do
            local member = mq.TLO.Group.Member(i)
            if not member.Dead() then
                local memberHP = member.PctHPs() or 100
                local distance = member.Distance3D() or 300
                if memberHP < config.get('HOTHEALPCT') and distance < 200 then
                    if memberHP < mostHurtPct or not mostHurtClass then
                        mostHurtName = member.CleanName()
                        mostHurtID = member.ID()
                        mostHurtPct = memberHP
                        mostHurtClass = member.Class.ShortName()
                        mostHurtDistance = distance
                    end
                    -- if memberHP < config.get('GROUPHEALPCT') and distance < 80 then numHurt = numHurt + 1 end
                    -- work around lazarus Group.MainTank never working, tank just a group member
                    if tankClasses[member.Class.ShortName()] and memberHP < config.get('PANICHEALPCT') and distance < 200 then
                        return member.ID(), HEAL_TYPES.PANIC, true
                    end
                end
                if healEnabled(options, 'HEALPET') then
                    local memberPetHP = member.Pet.PctHPs() or 100
                    local memberPetDistance = member.Pet.Distance3D() or 300
                    if memberPetHP < config.get('HEALPCT') and memberPetDistance < 200 then
                        mostHurtPetName = member.Pet.CleanName()
                        mostHurtPetID = member.Pet.ID()
                        mostHurtPetPct = memberPetHP
                        mostHurtPetDistance = memberPetDistance
                    end
                end
            end
        end
    end
    if mostHurtPct < config.get('PANICHEALPCT') then
        return mostHurtID, HEAL_TYPES.PANIC, true
    elseif numHurt >= config.get('GROUPHEALMIN') then
        return nil, HEAL_TYPES.GROUP, true
    elseif mostHurtPct < config.get('HEALPCT') and mostHurtDistance < 200 then
        return mostHurtID, ((tankClasses[mostHurtClass] or mostHurtName==config.get('PRIORITYTARGET')) and HEAL_TYPES.TANK) or HEAL_TYPES.REGULAR, true
    -- elseif mostHurtPct < config.get('HOTHEALPCT') and melees[mostHurtClass] and mostHurtDistance < 100 then
    --     local hotTimer = hottimers[mostHurtName]
    --     if (not hotTimer or hotTimer:expired()) then
    --         return mostHurtID, HEAL_TYPES.HOT
    --     end
    end
    if config.get('XTARGETHEAL') then
        mostHurtPct = 100
        for i=1,mq.TLO.Me.XTargetSlots() do
            local xtarSpawn = mq.TLO.Me.XTarget(i)
            local xtarType = xtarSpawn.Type()
            if xtarType == 'PC' or xtarType == 'Pet' then
                local xtargetHP = xtarSpawn.PctHPs() or 100
                local xtarDistance = xtarSpawn.Distance3D() or 300
                if xtargetHP < config.get('HOTHEALPCT') and xtarDistance < 200 then
                    if xtargetHP < mostHurtPct or not mostHurtClass then
                        mostHurtName = xtarSpawn.CleanName()
                        mostHurtID = xtarSpawn.ID()
                        mostHurtPct = xtargetHP
                        mostHurtClass = xtarType == 'PC' and xtarSpawn.Class.ShortName() or nil
                        mostHurtDistance = xtarDistance
                    end
                end
            end
        end
        if mostHurtPct < config.get('PANICHEALPCT') then
            return mostHurtID, HEAL_TYPES.PANIC, false
        elseif mostHurtPct < config.get('HEALPCT') and mostHurtDistance < 200 then
            return mostHurtID, ((tankClasses[mostHurtClass] or mostHurtName==config.get('PRIORITYTARGET')) and HEAL_TYPES.TANK) or HEAL_TYPES.REGULAR, false
        -- elseif mostHurtPct < config.get('HOTHEALPCT') and melees[mostHurtClass] and mostHurtDistance < 100 then
        --     local hotTimer = hottimers[mostHurtName]
        --     if (not hotTimer or hotTimer:expired()) then
        --         return mostHurtID, HEAL_TYPES.HOT
        --     end
        end
    end
    if mostHurtPetID ~= 0 and mostHurtPetDistance < 200 then
        return mostHurtPetID, mostHurtPetName == config.get('PRIORITYTARGET') and HEAL_TYPES.TANK or HEAL_TYPES.REGULAR, false
    end
    return nil, HEAL_TYPES.GROUPHOT, true
end

local groupHOTTimer = timer:new(60000)
local function getHeal(healAbilities, healType, whoToHeal, options, inGroup)
    for _,heal in ipairs(healAbilities) do
        if heal[healType] and healEnabled(options, heal.opt) then
            if inGroup or (not inGroup and not heal.group and not heal.grouppanic) then
                if not heal.tot or (mq.TLO.Me.CombatState() == 'COMBAT' and whoToHeal ~= mq.TLO.Me.ID()) then
                    if healType == HEAL_TYPES.GROUPHOT then
                        if mq.TLO.Me.CombatState() == 'COMBAT' and groupHOTTimer:expired() and not mq.TLO.Me.Song(heal.Name)() and heal:isReady() == abilities.IsReady.SHOULD_CAST then return heal end
                    elseif heal.CastType == abilities.Types.Spell then
                        local spell = mq.TLO.Spell(heal.Name)
                        if abilities.canUseSpell(spell, heal) == abilities.IsReady.CAN_CAST then
                            return heal
                        end
                    elseif heal.CastType == abilities.Types.Item then
                        local theItem = mq.TLO.FindItem(heal.ID)
                        if heal:isReady(theItem) == abilities.IsReady.SHOULD_CAST then return heal end
                    else
                        if heal:isReady() == abilities.IsReady.SHOULD_CAST then return heal end
                    end
                end
            end
        end
    end
end

function healing.heal(healAbilities, options)
    local whoToHeal, typeOfHeal, inGroup = getHurt(options)
    local healToUse = getHeal(healAbilities, typeOfHeal, whoToHeal, options, inGroup)
    if not healToUse and typeOfHeal == HEAL_TYPES.PANIC then
        healToUse = getHeal(healAbilities, HEAL_TYPES.REGULAR, whoToHeal, options)
    elseif not healToUse and typeOfHeal == HEAL_TYPES.GROUPPANIC then
        healToUse = getHeal(healAbilities, HEAL_TYPES.GROUP, whoToHeal, options)
    end
    logger.debug(logger.flags.routines.heal, string.format('heal %s %s %s', whoToHeal, typeOfHeal, healToUse and healToUse.name or ''))
    if healToUse and (healToUse.CastType ~= abilities.Types.Spell or not mq.TLO.Me.SpellInCooldown()) then
        if whoToHeal and mq.TLO.Target.ID() ~= whoToHeal then
            -- mq.cmdf('/mqt id %s', whoToHeal)
            mq.TLO.Spawn('id '..whoToHeal).DoTarget()
        end
        if abilities.use(healToUse) then return true end
        -- if typeOfHeal == HEAL_TYPES.HOT then
            -- local targetName = mq.TLO.Target.CleanName()
            -- if not targetName then return end
            -- local hotTimer = hottimers[targetName]
            -- if not hotTimer then
            --     hottimers[targetName] = timer:new(60000)
            -- else
            --     hotTimer:reset()
            -- end
        -- end
    end
    for toon,data in pairs(state.actors) do
        local wantBuffs = data.wantBuffs
        if wantBuffs then
            for _,buffAlias in ipairs(wantBuffs) do
                if buffAlias == 'HOT' then
                    local healToUse = getHeal(healAbilities, HEAL_TYPES.HOT, toon, options)
                    if healToUse then
                        mq.TLO.Spawn('pc ='..toon).DoTarget()
                        if abilities.use(healToUse) then return true end
                    end
                end
            end
        end
    end
end

function healing.healPetOrSelf(healAbilities, options)
    local myHP = mq.TLO.Me.PctHPs()
    local petHP = mq.TLO.Pet.PctHPs() or 100
    if myHP < 60 then healing.healSelf(healAbilities, options) end
    if not healEnabled(options, 'HEALPET') then return end
    for _,heal in ipairs(healAbilities) do
        if heal.pet and petHP < heal.pet then
            if abilities.use(heal) then
                return true
            end
        end
    end
end

function healing.healSelf(healAbilities, options)
    if mq.TLO.Me.PctHPs() > config.get('HEALPCT') then return end
    for _,heal in ipairs(healAbilities) do
        if heal.self and healEnabled(options, heal.opt) then
            local originalTargetID = mq.TLO.Target.ID()
            if heal.TargetType == 'Single' and abilities.canUseSpell(mq.TLO.Spell(heal.SpellName), heal) == abilities.IsReady.CAN_CAST then
                mq.TLO.Me.DoTarget()
            end
            if abilities.use(heal) then
                state.queuedAction = function()
                    if originalTargetID ~= mq.TLO.Target.ID() then mq.cmdf('/squelch /mqt id %s', originalTargetID) end
                end
                return true
            end
        end
    end
end

local newCorpses = {}
local function doRezFor(rezAbility)
    local waitForZoning = true
    local corpse = mq.TLO.Spawn('pccorpse '..mq.TLO.Me.CleanName()..'\'s corpse radius 100')
    if not corpse() then
        corpse = mq.TLO.Spawn('pccorpse tank radius 100 noalert 0')
        if not corpse() then
            corpse = mq.TLO.Spawn('pccorpse healer radius 100 noalert 0')
            if not corpse() then
                corpse = mq.TLO.Spawn('pccorpse radius 100 noalert 0')
                if not corpse() then
                    return false
                end
            end
        end
    else
        -- my own corpse, no need to wait
        waitForZoning = false
    end
    local corpseName = corpse.Name()
    if not corpseName then return false end
    corpseName = corpseName:gsub('\'s corpse.*', '')
    if (config.get('REZGROUP') and mq.TLO.Group.Member(corpseName)()) or (config.get('REZRAID') and mq.TLO.Raid.Member(corpseName)()) then
        -- no corpse to rez
        if mq.TLO.Zone.ShortName() ~= 'poknowledge' then
            if not newCorpses[corpseName] and waitForZoning then
                -- don't try to rez a freshly seen corpse immediately, because zone times
                newCorpses[corpseName] = timer:new(3000)
                return false
            end
            -- if corpse has been seen before but too fresh, don't rez yet
            if newCorpses[corpseName] and not newCorpses[corpseName]:expired() then return false end
        end
        corpse.DoTarget()
        if mq.TLO.Target.Type() == 'Corpse' then
            mq.cmd('/keypress CONSIDER')
            mq.delay(300)
            mq.doevents('eventCannotRezNew')
            if state.cannotRez then
                mq.cmdf('/squelch /alert add 0 id %s', corpse.ID())
                state.cannotRez = nil
                reztimer:reset()
                return false
            end
            mq.cmd('/corpse')
            mq.delay(50)
            if mq.TLO.Target.Type() == 'Corpse' and abilities.use(rezAbility) then
                mq.cmdf('/squelch /alert add 0 id %s', corpse.ID())
                reztimer:reset()
                return true
            end
        end
    else
        mq.cmdf('/squelch /alert add 0 id %s', corpse.ID())
    end
end

local rezCheckTimer = timer:new(5000)
function healing.rez(rezAbility)
    if (mq.TLO.Zone.ShortName() ~= 'poknowledge' and not rezCheckTimer:expired()) or not rezAbility then return end
    rezCheckTimer:reset()
    if not config.get('REZINCOMBAT') and mq.TLO.Me.CombatState() == 'COMBAT' then return end
    if rezAbility.CastType == abilities.Types.AA and not mq.TLO.Me.AltAbilityReady(rezAbility.CastName)() then
        return
    elseif rezAbility.CastType == abilities.Types.Spell and not mq.TLO.Me.SpellReady(rezAbility.CastName)() then
        return
    elseif rezAbility.CastType == abilities.Types.Item and not mq.TLO.Me.ItemReady(rezAbility.CastName)() then
        return
    end
    if mq.TLO.Me.Class.ShortName() == 'NEC' and mq.TLO.FindItemCount('=Essence Emerald')() == 0 then return end
    if rezAbility.CastName == 'Token of Resurrection' and (mq.TLO.FindItemCount('=Token of Resurrection')() == 0 or mq.TLO.Me.CombatState() ~= 'COMBAT') then return end
    if reztimer:expired() and mq.TLO.Alert(0)() then mq.cmd('/squelch /alert clear 0') newCorpses = {} end
    return doRezFor(rezAbility)
end

return healing