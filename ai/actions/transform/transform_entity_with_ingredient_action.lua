local Entity = _radiant.om.Entity
local TransformWithIngredient = radiant.class()

TransformWithIngredient.name = 'transform'
TransformWithIngredient.does = 'stonehearth_ace:transform_entity_with_ingredient'
TransformWithIngredient.args = {
   item = Entity,          -- The item to be transformed
   ingredient = 'table'    -- the ingredient to use for transforming
}
TransformWithIngredient.priority = 0.5

function TransformWithIngredient:start_thinking(ai, entity, args)
   local transform_comp = args.item and args.item:is_valid() and args.item:get_component('stonehearth_ace:transform')
   if transform_comp and transform_comp:can_transform_with(entity) then
      ai:set_think_output({})
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(TransformWithIngredient)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:job:work_player_id_changed',
         })
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:job_changed',
         })
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:pickup_ingredient', { ingredient = ai.ARGS.ingredient })
         :execute('stonehearth:goto_entity', { entity = ai.ARGS.item })
         :execute('stonehearth:reserve_entity', { entity = ai.ARGS.item })
         :execute('stonehearth_ace:transform_adjacent', { item = ai.ARGS.item })
