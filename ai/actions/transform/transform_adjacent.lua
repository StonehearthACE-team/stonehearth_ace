local Entity = _radiant.om.Entity
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local TransformItemAdjacent = radiant.class()

TransformItemAdjacent.name = 'transform adjacent'
TransformItemAdjacent.does = 'stonehearth_ace:transform_adjacent'
TransformItemAdjacent.args = {
   item = Entity,      -- the entity to transform
}
TransformItemAdjacent.priority = 0

function TransformItemAdjacent:start(ai, entity, args)
   -- TODO: check to make sure we'll be next to the entity
   local key
   if radiant.entities.get_entity_data(args.item, 'stonehearth_ace:buildable_data') then
      key = 'build'
   else
      key = 'transform'
   end
   ai:set_status_text_key('stonehearth_ace:ai.actions.status_text.' .. key, { target = args.item })

   self._destroy_listener = radiant.events.listen_once(args.item, 'radiant:entity:pre_destroy', function()
      if not self._completed_work then
         ai:abort()
      end
   end)
end

function TransformItemAdjacent:stop(ai, entity, args)
   local transform_comp = args.item and args.item:is_valid() and args.item:get_component('stonehearth_ace:transform')
   if transform_comp then
      transform_comp:_destroy_effect()
   end

   if self._destroy_listener then
      self._destroy_listener:destroy()
      self._destroy_listener = nil
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
         local progress = transform_comp:get_progress()

         if duration then
            -- determine how long the effect will last based on previous progress
            local this_duration = stonehearth.calendar:parse_duration(duration, true) * (1 - progress:get_progress_percentage())

            ai:execute('stonehearth:run_effect_timed', { effect = effect, duration = this_duration})
         else
            progress:set_max_progress(data.transforming_worker_effect_times)

            for i = 1, times or 1 do
               if progress:is_finished() then
                  break
               end

               ai:execute('stonehearth:run_effect', { effect = effect})
               progress:increment_progress()
            end
         end
         self._completed_work = true
         transformed_form = transform_comp:transform()
      else
         self._completed_work = true
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
         transform_comp:spawn_additional_items(entity, location)
		end
		
      if data and data.worker_finished_effect then
         ai:execute('stonehearth:run_effect', { effect = data.worker_finished_effect})
      end
   end
end

return TransformItemAdjacent
