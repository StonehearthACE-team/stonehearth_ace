local rng = _radiant.math.get_default_rng()

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
         self:_set_quality(carrying, self._crop)
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

function AceHarvestCropAdjacent:_get_actual_spawn_count(entity)
   local num_to_spawn = 1
   
   local job_component = entity:get_component('stonehearth:job')
   if job_component then
      if job_component:curr_job_has_perk('farmer_harvest_increase') or job_component:curr_job_has_perk('farmer_harvest_increase_100') then
         num_to_spawn = 2
      elseif job_component:curr_job_has_perk('farmer_harvest_increase_40') then
         num_to_spawn = math.floor(rng:get_real(1.4, 2.4))
      elseif job_component:curr_job_has_perk('farmer_harvest_increase_70') then
         num_to_spawn = math.floor(rng:get_real(1.7, 2.7))
      end
   end

   return num_to_spawn
end

function AceHarvestCropAdjacent:_set_quality(item, source)
   local source_iq = source:get_component('stonehearth:item_quality')
   local item_iq = item:add_component('stonehearth:item_quality')
   item_iq:initialize_quality(source_iq:get_quality(), source_iq:get_author_name(), source_iq:get_author_type(), {override_allow_variable_quality = true})
end

return AceHarvestCropAdjacent
