---@type Mq
local mq = require('mq')

local required_zone =   {
        ['akhevatwo_mission'] = true,
        ['akhevatwo_raid'] = true,
    }
local bane_mob_name = 'datiar xi tavuelim'

local banes = {
    CLR={
      {name='Blessed Chains',type='aa', order='1'},
      {name='Shackle',type='spell', order='2'}
    },
    BRD={
      {name='Slumber of Suja',type='spell',order='1'},
      {name='Wave of Stupor',type='spell',order='2'}
    },
    ENC={
      {name='Beam of Slumber',type='aa',order='1'},
      {name='Greater Fetter',type='spell',order='3'},--updated from Shackle since it does not apply to enc 5_8_24
      {name='Beguiler\'s Banishment',type='aa',order='2'},
      {name='Flummox',type='spell',order='4'}--added level 125 mez spell 5_8_24
    },
    PAL={
      {name='Shackles of Tunare',type='aa',order='1'},
      {name='Shackle',type='spell',order='2'}
    },
    SHM={
      {name='Shackle',type='spell',order='3'},
      {name='Spiritual Rebuke',type='aa',order='1'},
      {name='Virulent Paralysis',type='aa',order='2'}
    },
    NEC={
      {name='Pestilent Paralysis',type='aa',order='1'},
      {name='Shackle',type='spell',order='2'}
    },
    DRU={
      {name='Paralytic Spray',type='aa',order='1'},
      {name='Paralytic Spores',type='aa',order='2'},
      {name='Vinelash Assault',type='spell',order='3'},
    },
    RNG={
      {name='Grasp of Sylvan Spirits',type='aa',order='1'},
      {name='Vinelash Assault',type='spell',order='2'},
      {name='Blusterbolt',type='spell',order='3'},
      {name='Flusterbolt',type='spell',order='4'},
      {name='Enveloping Roots',type='spell',order='5'},
    },
    WIZ={
      {name='Frost Shackles',type='aa',order='1'},
      {name='Strong Root',type='aa',order='2'},
      {name='Restless Ice Block',type='spell',order='3'},
      {name='Ice Block',type='spell',order='4'}
    }
  }
local unbreakable = {
    ['CLR'] = true,
    --['DRU'] = true,
    --['SHM'] = true,
}

local function StopDPS()
    mq.cmd('/squelch /mqp on')
    mq.cmd('/squelch /rdpause on')
    mq.delay(10)
    if mq.TLO.Me.Class.ShortName() == 'BRD' then
        mq.cmd('/squelch /stopsong')
        mq.delay(10)
        mq.cmd('/squelch /stopsong')
        mq.delay(10)
    end
    mq.cmd('/squelch /rdpause on')
    mq.delay(10)
        if (mq.TLO.Me.Casting.ID()) and (not unbreakable[mq.TLO.Me.Class.ShortName()]) then
            mq.cmd('/squelch /stopcast')
            mq.delay(100)
        end
end
local function ResumeDPS()
   mq.cmd('/squelch /mqp off')
   mq.cmd('/squelch /rdpause off')
   mq.delay(10)
   --if mq.TLO.Me.Class.ShortName() == 'BRD' then
    --mq.cmd('/squelch /twist on')
    --mq.delay(10)
   --end
   mq.cmd('/squelch /rdpause off')
   mq.delay(10)
end
local function on_load()
    if not required_zone[mq.TLO.Zone.ShortName()]  then return end
    math.randomseed(os.time()*mq.TLO.Me.ID())
    local bane = banes[mq.TLO.Me.Class.ShortName()]
    if not bane then
        print('Sadly I will be of no help here')
        return end
    for _, data in ipairs(bane) do
        if data.type == 'spell' then
            local Spellname = mq.TLO.Spell(data.name).RankName()
            if mq.TLO.Me.Gem(Spellname)() and mq.TLO.Me.Gem(Spellname)() > 0 then
                print('Spell ', data.name,' memmed, good boy')
            else
                print('Spell ', data.name,' not memmed, you suck')
            end
        end
    end
end
local function isBaneableMob(spawn)
-- 200 should be enough
          return ((spawn.Type() == 'NPC') and (spawn.CleanName() == bane_mob_name) and (spawn.LineOfSight()) and (spawn.Distance() <  200))
end
---@return boolean @Returns true if the action should fire, otherwise false.
local function condition()
    local bane_mob_spawn = mq.getFilteredSpawns(isBaneableMob)
    return required_zone[mq.TLO.Zone.ShortName()] and #bane_mob_spawn > 0
end


local function target_bane_mob()
    local bane_mob_spawn = mq.getFilteredSpawns(isBaneableMob)
    local bane_mob_count = #bane_mob_spawn
    if bane_mob_count > 1 then
        --random defeates distance sorting, might weight it
        --table.sort(bane_mob_spawn, function(a, b) return a['Distance'] > b['Distance'] end )
        Index = math.random(bane_mob_count)
    else Index = 1
    end
    if #bane_mob_spawn > 0 then
        mq.cmdf('/mqtar ${Spawn[%s]}', bane_mob_spawn[Index]['ID'])
        mq.delay(50)
        mq.cmd('/face fast')
    end
end
local function cast(spell)
    if mq.TLO.Target.CleanName() == bane_mob_name then
        mq.cmdf('/cast %s', spell.RankName())
        mq.cmdf('/dgtell all used %s for bane on [%s] -- [%s]', spell.RankName(), mq.TLO.Target.CleanName(), mq.TLO.Target.ID())
        mq.delay(50+spell.MyCastTime())  
    end
end
local function use_aa(aa)
    if mq.TLO.Target.CleanName() == bane_mob_name then
        mq.cmdf('/alt activate %s', aa.ID())
        mq.cmdf('/dgtell all used %s for bane on [%s] -- [%s]', aa.Spell.Name(), mq.TLO.Target.CleanName(), mq.TLO.Target.ID())
        mq.delay(50+aa.Spell.CastTime())
    end
end
local function bane_ready(data)
    if not unbreakable[mq.TLO.Me.Class.ShortName()] then
        if data.type == 'spell' then
            return mq.TLO.Me.SpellReady(mq.TLO.Spell(data.name).RankName())()
        elseif data.type == 'aa' then
            return mq.TLO.Me.AltAbilityReady(data.name)()
        end
    else
        if data.type == 'spell' then
            return (mq.TLO.Me.SpellReady(mq.TLO.Spell(data.name).RankName())() and not mq.TLO.Me.Casting())
        elseif data.type == 'aa' then
            return (mq.TLO.Me.AltAbilityReady(data.name)() and not mq.TLO.Me.Casting())
        end
    end
end
local function action()
    print('Action!')
    local bane = banes[mq.TLO.Me.Class.ShortName()]
    -- if not a bane class, return
    if not bane then return end
    table.sort(bane, function(a, b) return a['order'] < b['order'] end )
    local breakcond = false
    while breakcond == false do
        local bane_mob_spawn = mq.getFilteredSpawns(isBaneableMob)
        if #bane_mob_spawn > 0 then
            for _, data in ipairs(bane) do
                if bane_ready(data) then
                    StopDPS()
                    target_bane_mob()
                    if data.type == 'spell' then
                        cast(mq.TLO.Spell(data.name))
                    else
                        use_aa(mq.TLO.Me.AltAbility(data.name))
                    end
                    while mq.TLO.Me.Casting() do
                        mq.delay(50)
                    end              
                    break
                end
            end
        else
            breakcond = true
            ResumeDPS()
        end
        mq.doevents()
        mq.delay(50)
    end
end
return {onload=on_load, condfunc=condition, actionfunc=action}
