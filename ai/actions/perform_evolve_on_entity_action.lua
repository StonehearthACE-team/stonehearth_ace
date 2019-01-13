local Entity = _radiant.om.Entity
local PerformEvolveOnItem = radiant.class()

PerformEvolveOnItem.name = 'perform evolve'
PerformEvolveOnItem.does = 'stonehearth_ace:perform_evolve_on_entity'
PerformEvolveOnItem.args = {
   owner_player_id = 'string',   -- the owner of the entity
   item = Entity,  -- The item to be evolved
}
PerformEvolveOnItem.priority = 0.5

function PerformEvolveOnItem:start_thinking(ai, entity, args)
   local evolve_data = radiant.entities.get_entity_data(args.item, 'stonehearth:evolve_data')
   if not evolve_data.evolve_ingredient then
      ai:set_think_output()
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(PerformEvolveOnItem)
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.ARGS.item
         })
         :execute('stonehearth:follow_path', {
            path = ai.PREV.path,
            stop_distance = ai.CALL(radiant.entities.get_harvest_range, ai.ENTITY),
         })
         :execute('stonehearth:add_buff', {buff = 'stonehearth:buffs:stopped', target = ai.ARGS.item})
         :execute('stonehearth_ace:perform_evolve_adjacent', {
            item = ai.ARGS.item,
            owner_player_id = ai.ARGS.owner_player_id,
         })
