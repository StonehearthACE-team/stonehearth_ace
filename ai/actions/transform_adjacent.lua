local Entity = _radiant.om.Entity
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local TransformItemAdjacent = radiant.class()

TransformItemAdjacent.name = 'transform adjacent'
TransformItemAdjacent.does = 'stonehearth_ace:transform_adjacent'
TransformItemAdjacent.args = {
   item = Entity,      -- the entity to transform
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
}
TransformItemAdjacent.priority = 0

function TransformItemAdjacent:start(ai, entity, args)
   -- TODO: check to make sure we'll be next to the entity
   ai:set_status_text_key('stonehearth_ace:ai.actions.status_text.transform', { target = args.item })
end

function TransformItemAdjacent:stop(ai, entity, args)
   local transform_comp = args.item and args.item:is_valid() and args.item:get_component('stonehearth_ace:transform')
   if transform_comp then
      transform_comp:_destroy_effect()
   end
end

function TransformItemAdjacent:run(ai, entity, args)
   local item = args.item
   local item_id = item:get_id()
   local transform_comp = item:get_component('stonehearth_ace:transform')
   local data = transform_comp:get_transform_options()

   if transform_comp and data then
      radiant.entities.turn_to_face(entity, item)
      ai:unprotect_argument(item)

      local effect = data.transforming_worker_effect
      local times = data.transforming_worker_effect_times
      local duration = data.transforming_effect_duration
      local ingredient = data.transform_ingredient_uri or data.transform_ingredient_material
      local ing_item
      
      if ingredient then
         ing_item = radiant.entities.get_carrying(entity)
         ai:execute('stonehearth:drop_carrying_now')
      end

      local transformed_form
      if effect then
         transform_comp:perform_transform()
         if duration then
            ai:execute('stonehearth:run_effect_timed', { effect = effect, duration = duration})
         else
            for i = 1, times or 1 do
               ai:execute('stonehearth:run_effect', { effect = effect})
            end
         end
         transformed_form = transform_comp:transform()
      else
         transformed_form = transform_comp:perform_transform(true)
      end

      if ing_item and ing_item:is_valid() then
         -- apply item quality here if relevant, rather than in the transform component
         -- because it would be a mess in there passing it around or having to store it
         if data.apply_ingredient_quality and transformed_form then
            item_quality_lib.copy_quality(ing_item, transformed_form)
         end

         ai:unprotect_argument(ing_item)
         radiant.entities.destroy_entity(ing_item)
      end

		if data.additional_items then
			local location = radiant.entities.get_world_grid_location(entity)
         transform_comp:spawn_additional_items(entity, location, args.owner_player_id)
		end
		
      if data and data.worker_finished_effect then
         ai:execute('stonehearth:run_effect', { effect = data.worker_finished_effect})
      end
   end
end

return TransformItemAdjacent
