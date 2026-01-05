local Entity = _radiant.om.Entity
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
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
   self._ai = ai
   self._entity = entity

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
      local location = radiant.entities.get_world_grid_location(item)
      radiant.entities.turn_to_face(entity, location)

      local effect = data.transforming_worker_effect
      local times = data.transforming_worker_effect_times
      local duration = data.transforming_effect_duration
      local apply_ingredient_quality = data.apply_ingredient_quality
      local use_timed_progress = (times or 1) < 2
      local ingredient = data.transform_ingredient_uri or data.transform_ingredient_material
      local ing_item, ing_root, ing_quality
      local ing_options = {}
      local finish_data = {
         transform_comp = transform_comp,
         ing_options = ing_options,
         apply_ingredient_quality = apply_ingredient_quality,
         location = location,
      }

      if ingredient then
         ing_item = radiant.entities.get_carrying(entity)
         if ing_item and ing_item:is_valid() then
            -- Save the ingredient's quality so that it can be applied onto the transformed form after the ingredient itself is gone
            ing_root = entity_forms_lib.get_root_entity(ing_item) or ing_item
            local iq = ing_root:get_component('stonehearth:item_quality')
            if iq and iq:get_quality() > 1 then
               ing_quality = iq:get_quality()
               ing_options.author = iq:get_author_name()
               ing_options.author_type = iq:get_author_type()
            end

            finish_data.ing_item = ing_item
            finish_data.ing_root = ing_root
            finish_data.ing_quality = ing_quality
         end
         ai:execute('stonehearth:drop_carrying_into_entity_adjacent', { entity = args.item })
      end

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
         finish_data.transformed_form = transform_comp:transform(entity, ing_root)
         self:_finish(finish_data)
      else
         self._completed_work = true
         ai:unprotect_argument(item)
         radiant.events.listen(entity, 'stonehearth_ace:transform:perform_transform:complete', function(e)
               finish_data.transformed_form = e.transformed_form
               self:_finish(finish_data, true)
            end)
         transform_comp:perform_transform(true, entity)
         ai:suspend('perform_transform')
      end
   end
end

function TransformItemAdjacent:_finish(data, resume_ai)
   -- if transformation failed, pick up the ingredient (if there was one) and cancel
   if not data.transformed_form then
      if data.ing_root then
         stonehearth.ai:pickup_item(self._ai, self._entity, data.ing_item)
         self._ai:execute('stonehearth:run_pickup_effect', { location = data.location })
      end

      if resume_ai then
         self._ai:resume('perform_transform')
      end
      return
   end

   -- Apply the copied quality of the ingredient (if there was one) to the transformed form
   if data.apply_ingredient_quality and data.transformed_form and data.ing_quality and data.ing_options then
      item_quality_lib.apply_quality(data.transformed_form, data.ing_quality, data.ing_options)
   end

   -- If, for whatever reason, the ingredient still exists - destroy it
   if data.ing_root and data.ing_root:is_valid() and data.destroy_ingredient ~= false then
      self._ai:unprotect_argument(data.ing_root)
      radiant.entities.destroy_entity(data.ing_root)
   end

   if data.additional_items then
      local location = radiant.entities.get_world_grid_location(self._entity)
      data.transform_comp:spawn_additional_items(self._entity, location)
   end

   if data and data.worker_finished_effect then
      self._ai:execute('stonehearth:run_effect', { effect = data.worker_finished_effect})
   end

   if resume_ai then
      self._ai:resume('perform_transform')
   end
end

return TransformItemAdjacent
