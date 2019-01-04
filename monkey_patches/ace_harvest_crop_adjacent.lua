local Point3 = _radiant.csg.Point3
local Entity = _radiant.om.Entity

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

   -- bump up the count on the one we're carrying.
   if carrying then
      radiant.entities.increment_carrying(entity, self._spawn_count)
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
      stacks_component:set_stacks(1)
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

--By default, we produce 1 item stack per basket
function HarvestCropAdjacent:_get_num_to_increment(entity)
   local num_to_spawn = 1

   --If the this entity has the right perk, spawn more than one
   local job_component = entity:get_component('stonehearth:job')
   if job_component and job_component:curr_job_has_perk('farmer_harvest_increase') then
      num_to_spawn = 2
   end

   return num_to_spawn
end

function AceHarvestCropAdjacent:_can_carry_more(entity, carrying)
   assert(self._spawn_count)

   local stacks_component = carrying:get_component('stonehearth:stacks')
   if not stacks_component or (stacks_component:get_stacks() + self._spawn_count >= stacks_component:get_max_stacks()) then
      return false
   end
   return true
end

function AceHarvestCropAdjacent:_get_max_spawn_count(entity)
   local job_component = entity:get_component('stonehearth:job')
   if job_component then
      if job_component:curr_job_has_perk('farmer_harvest_increase') then
         num_to_spawn = 2
      end
   end
end

return AceHarvestCropAdjacent
