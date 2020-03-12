local Entity = _radiant.om.Entity

local ClearHerbalistPlanter = radiant.class()

ClearHerbalistPlanter.name = 'clear herbalist planter'
ClearHerbalistPlanter.does = 'stonehearth_ace:clear_herbalist_planter'
ClearHerbalistPlanter.args = {
   planter = Entity,    -- the planter that needs to be cleared
}
ClearHerbalistPlanter.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(ClearHerbalistPlanter)
         :execute('stonehearth:goto_entity', { entity = ai.ARGS.planter })
         :execute('stonehearth:reserve_entity', { entity = ai.ARGS.planter })
         :execute('stonehearth_ace:clear_herbalist_planter_adjacent', {
            planter = ai.ARGS.planter
         })
