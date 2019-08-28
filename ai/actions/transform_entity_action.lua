local Entity = _radiant.om.Entity
local TransformItem = radiant.class()

TransformItem.name = 'transform'
TransformItem.does = 'stonehearth_ace:transform_entity'
TransformItem.args = {
   owner_player_id = 'string',   -- the owner of the entity
   item = Entity,  -- The item to be transformed
}
TransformItem.priority = 0.5

function TransformItem:start_thinking(ai, entity, args)
   local transform_comp = args.item:get_component('stonehearth_ace:transform')
   local transform_data = transform_comp:get_transform_options()
   if transform_data and not transform_data.transform_ingredient_uri and not transform_data.transform_ingredient_material then
      ai:set_think_output()
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(TransformItem)
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
            owner_player_id = ai.ARGS.owner_player_id,
         })
