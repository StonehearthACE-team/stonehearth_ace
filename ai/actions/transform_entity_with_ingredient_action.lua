local Entity = _radiant.om.Entity
local TransformWithIngredient = radiant.class()

TransformWithIngredient.name = 'transform'
TransformWithIngredient.does = 'stonehearth_ace:transform_entity'
TransformWithIngredient.args = {
   owner_player_id = 'string',   -- the owner of the entity
   item = Entity,  -- The item to be transformed
}
TransformWithIngredient.priority = 1.0

function TransformWithIngredient:start_thinking(ai, entity, args)
   local transform_data = radiant.entities.get_entity_data(args.item, 'stonehearth_ace:transform_data')
   if transform_data.transform_ingredient_uri then
      ai:set_think_output({ ingredient = {uri = transform_data.transform_ingredient_uri} })
   elseif transform_data.transform_ingredient_material then
      ai:set_think_output({ ingredient = {material = transform_data.transform_ingredient_material} })
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(TransformWithIngredient)
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
         :execute('stonehearth_ace:transform_adjacent', {
            item = ai.ARGS.item,
            owner_player_id = ai.ARGS.owner_player_id
         })
