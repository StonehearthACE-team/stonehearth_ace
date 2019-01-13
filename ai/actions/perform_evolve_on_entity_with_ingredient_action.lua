local Entity = _radiant.om.Entity
local PerformEvolveWithIngredient = radiant.class()

PerformEvolveWithIngredient.name = 'perform evolve'
PerformEvolveWithIngredient.does = 'stonehearth_ace:perform_evolve_on_entity'
PerformEvolveWithIngredient.args = {
   owner_player_id = 'string',   -- the owner of the entity
   item = Entity,  -- The item to be evolved
}
PerformEvolveWithIngredient.priority = 1.0

function PerformEvolveWithIngredient:start_thinking(ai, entity, args)
   local evolve_data = radiant.entities.get_entity_data(args.item, 'stonehearth:evolve_data')
   if evolve_data.evolve_ingredient_uri then
      ai:set_think_output({ ingredient = {uri = evolve_data.evolve_ingredient_uri} })
   elseif evolve_data.evolve_ingredient_material then
      ai:set_think_output({ ingredient = {material = evolve_data.evolve_ingredient_material} })
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(PerformEvolveWithIngredient)
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:pickup_ingredient', { ingredient = ai.BACK(2).ingredient })
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
            owner_player_id = ai.ARGS.owner_player_id
         })
