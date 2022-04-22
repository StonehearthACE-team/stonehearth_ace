local Entity = _radiant.om.Entity
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local TransformItemAdjacent = radiant.class()

local log = radiant.log.create_logger('transform_adjacent')

TransformItemAdjacent.name = 'transform adjacent'
TransformItemAdjacent.does = 'stonehearth_ace:transform_adjacent'
TransformItemAdjacent.args = {
   item = Entity,      -- the entity to transform
}
TransformItemAdjacent.priority = 0

function TransformItemAdjacent:start(ai, entity, args)
   -- TODO: check to make sure we'll be next to the entity
   local key, full_key
   if radiant.entities.get_entity_data(args.item, 'stonehearth_ace:transform_data').status_key then
      full_key = tostring(radiant.entities.get_entity_data(args.item, 'stonehearth_ace:transform_data').status_key)
   elseif radiant.entities.get_entity_data(args.item, 'stonehearth_ace:buildable_data') then
      key = 'build'
   else
      key = 'transform'
   end

   if full_key then
      ai:set_status_text_key(full_key, { target = args.item })
   else
      ai:set_status_text_key('stonehearth_ace:ai.actions.status_text.' .. key, { target = args.item })
   end

   self._completed_work = false

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
   if not transform_comp:is_transformable() then
      ai:abort('not transformable!')
      return
   end

   local data = transform_comp:get_transform_options()

   if transform_comp and data then
      -- face the center of the entity instead of the edge
      radiant.entities.turn_to_face(entity, radiant.entities.get_world_grid_location(item))

      local effect = data.transforming_worker_effect
      local times = data.transforming_worker_effect_times
      local duration = data.transforming_effect_duration
      local use_timed_progress = (times or 1) < 2
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
            if radiant.util.is_string(duration) then
               duration = stonehearth.calendar:parse_duration(duration)
            end
            local this_duration = duration * (1 - progress:get_progress_percentage())

            log:debug('running effect %s for %s (of %s)', effect, this_duration, duration)
            ai:execute('stonehearth:run_effect_timed', { effect = effect, duration = this_duration})
         else
            -- if the effect will run fewer than 2 times, use time tracking instead
            -- briefly create an effect in order to get its duration
            if use_timed_progress then
               local temp_effect = radiant.effects.run_effect(entity, effect)
               local duration = stonehearth.calendar:realtime_to_game_seconds(temp_effect._finish_timer:get_duration() * (times or 1), true)
               progress:start_time_tracking(duration)
               temp_effect:stop()
            else
               progress:set_max_progress(data.transforming_worker_effect_times)
            end

            for i = 1, times or 1 do
               if progress:is_finished() then
                  break
               end

               ai:execute('stonehearth:run_effect', { effect = effect})
               if not use_timed_progress then
                  progress:increment_progress()
               end
            end
         end
         self._completed_work = true
         ai:unprotect_argument(item)
         transformed_form = transform_comp:transform(entity)
      else
         self._completed_work = true
         ai:unprotect_argument(item)
         transformed_form = transform_comp:perform_transform(true, entity)
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
