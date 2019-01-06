local rng = _radiant.math.get_default_rng()

local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'

local HarvestCropAdjacent = require 'stonehearth.ai.actions.harvest_crop_adjacent'
local AceHarvestCropAdjacent = class()

function AceHarvestCropAdjacent:_harvest_one_time(ai, entity)
   assert(self._crop and self._crop:is_valid())

   local carrying = radiant.entities.get_carrying(entity)

   -- make sure we can pick up more of the crop
   if carrying then
      if not self:_can_carry_more(entity, carrying) then
         return false
      end
   end

   -- all good!  harvest once
   radiant.entities.turn_to_face(entity, self._crop)
   ai:execute('stonehearth:run_effect', { effect = 'fiddle' })

   local harvest_count = self:_get_actual_spawn_count(entity)
   local crop_quality = radiant.entities.get_item_quality(self._crop)

   -- bump up the count on the one we're carrying.
   if carrying then
      radiant.entities.increment_carrying(entity, harvest_count)
      -- make sure the quality is applied
      local carrying_quality = radiant.entities.get_item_quality(carrying)
      if crop_quality > carrying_quality then
         local stacks_component = product:get_component('stonehearth:stacks')
         local new_carrying = radiant.entities.create_entity(carrying:get_uri(), {owner = carrying})
         if stacks_component then
            new_carrying:add_component('stonehearth:stacks'):set_stacks(stacks_component:get_stacks())
         end
         self:_set_quality(new_carrying, self._crop)

         radiant.entities.remove_carrying(carrying)
         radiant.entities.destroy_entity(carrying)

         radiant.entities.pickup_item(entity, new_carrying)
         -- newly harvested drops go into your inventory immediately unless your inventory is full
         stonehearth.inventory:get_inventory(radiant.entities.get_player_id(entity))
                                 :add_item_if_not_full(new_carrying)
      end

      return true
   end

   -- oops, not carrying!  stick something in our hands.
   local product_uri = self._crop:get_component('stonehearth:crop')
                                    :get_product()

   if not product_uri then
      -- Product is nil likely because the crop has rotted in the field.
      -- We should just destroy it and keep going.
      return true
   end

   local product = radiant.entities.create_entity(product_uri, { owner = entity })
   local entity_forms = product:get_component('stonehearth:entity_forms')

   --If there is an entity_forms component, then you want to put the iconic version
   --in the farmer's arms, not the actual entity (ie, if we had a chair crop)
   --This also prevents the item component from being added to the full sized versions of things.
   if entity_forms then
      local iconic = entity_forms:get_iconic_entity()
      if iconic then
         product = iconic
      end
   end

   local stacks_component = product:get_component('stonehearth:stacks')
   if stacks_component then
      stacks_component:set_stacks(harvest_count)
   end

   if crop_quality > 1 then
      self:_set_quality(product, self._crop)
   end

   radiant.entities.pickup_item(entity, product)

   -- newly harvested drops go into your inventory immediately unless your inventory is full
   stonehearth.inventory:get_inventory(radiant.entities.get_player_id(entity))
                           :add_item_if_not_full(product)

   --Fire the event that describes the harvest
   radiant.events.trigger(entity, 'stonehearth:harvest_crop', {crop_uri = self._crop:get_uri()})
   self._log:detail('destroying crop %s', tostring(self._crop))
   return true
end

AceHarvestCropAdjacent._old__get_num_to_increment = HarvestCropAdjacent._get_num_to_increment
function AceHarvestCropAdjacent:_get_num_to_increment(entity)
   local num_to_spawn = self:_old__get_num_to_increment(entity)

   local job_component = entity:get_component('stonehearth:job')
   if job_component then
      local harvest_increase_amount = job_component:get_curr_job_controller():get_lookup_value('harvest_increase_amount')
      if harvest_increase_amount then
         num_to_spawn = 1 + math.ceil(harvest_increase_amount)
      end
   end

   return num_to_spawn
end

function AceHarvestCropAdjacent:_get_actual_spawn_count(entity)
   local num_to_spawn = 1
   
   local job_component = entity:get_component('stonehearth:job')
   if job_component then
      if job_component:curr_job_has_perk('farmer_harvest_increase') then
         num_to_spawn = 2
      else
         local harvest_increase_amount = job_component:get_curr_job_controller():get_lookup_value('harvest_increase_amount')
         if harvest_increase_amount then
            num_to_spawn = math.ceil(rng:get_real(0.0001 + harvest_increase_amount, 1 + harvest_increase_amount))
         end
      end
   end

   return num_to_spawn
end

function AceHarvestCropAdjacent:_set_quality(item, source)
   item_quality_lib.copy_quality(source, item, {override_allow_variable_quality = true})
end

return AceHarvestCropAdjacent
