local rng = _radiant.math.get_default_rng()

local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'

local HarvestCropAdjacent = require 'stonehearth.ai.actions.harvest_crop_adjacent'
local AceHarvestCropAdjacent = class()

function AceHarvestCropAdjacent:start_thinking(ai, entity, args)
   self._log = ai:get_log()
   self._entity = entity
   self._spawn_count = self:_get_num_to_increment(entity)

   self._farmer_field = args.field_layer:get_component('stonehearth:farmer_field_layer')
                                    :get_farmer_field()

   self._crop = self._farmer_field:crop_at(args.location)
   self._origin = radiant.entities.get_world_grid_location(args.field_layer)

   if not self._crop or not self._crop:is_valid() then
      self._log:detail('no crop at %s (%s); removing from harvestable region', args.location, tostring(self._crop))
      self._farmer_field:notify_crop_destroyed(args.location.x - self._origin.x + 1, args.location.z - self._origin.z + 1)
      return
   end

   local carrying = ai.CURRENT.carrying
   if carrying then
      -- make sure it's the right crop...
      if not self:_is_same_crop(carrying, self._crop) then
         self._log:detail('not the same')
         return
      end
      -- make sure we can fit another load...
      if not self:_can_carry_more(entity, carrying) then
         self._log:detail('cannot carry more')
         return
      end
   end
   self._location = args.location
   self._destination = args.field_layer:get_component('destination')

   ai:protect_argument(self._crop)
   ai:set_think_output()
end

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

   local player_id = radiant.entities.get_work_player_id(self._entity)
   local harvest_count = self:_get_actual_spawn_count(entity)
   local crop_quality = radiant.entities.get_item_quality(self._crop)

   -- if the crop we're harvesting is a megacrop, handle that
   local crop_comp = self._crop and self._crop:get_component('stonehearth:crop')
   if crop_comp and crop_comp:is_megacrop() then
      if self:_harvest_megacrop_and_return(ai, player_id, crop_quality) then
         return true
      end
   end

   -- bump up the count on the one we're carrying.
   if carrying then
      radiant.entities.increment_carrying(entity, harvest_count)
      -- make sure the quality is applied
      local carrying_quality = radiant.entities.get_item_quality(carrying)
      if crop_quality > carrying_quality then
         local stacks_component = carrying:get_component('stonehearth:stacks')
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
   local product = self:_create_product(player_id, crop_quality, harvest_count)
   if not product then
      -- Product is nil likely because the crop has rotted in the field.
      -- We should just destroy it and keep going.
      return true
   end

   self:_pickup_item(player_id, product)

   --Fire the event that describes the harvest
   radiant.events.trigger(entity, 'stonehearth:harvest_crop', {crop_uri = self._crop:get_uri()})
   self._log:detail('destroying crop %s', tostring(self._crop))
   return true
end

AceHarvestCropAdjacent._ace_old__get_num_to_increment = HarvestCropAdjacent._get_num_to_increment
function AceHarvestCropAdjacent:_get_num_to_increment(entity)
   local num_to_spawn = self:_ace_old__get_num_to_increment(entity)

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
   item_quality_lib.copy_quality(source, item)
end

function AceHarvestCropAdjacent:_create_product(player_id, crop_quality, num_stacks, max_stacks)
   local crop_comp = self._crop:get_component('stonehearth:crop')
   if crop_comp then
      return self:_create_item(player_id, crop_comp:get_product(), crop_quality, num_stacks, max_stacks)
   end
end

function AceHarvestCropAdjacent:_create_item(player_id, uri, crop_quality, num_stacks, max_stacks)
   if not uri then
      return
   end

   local product = radiant.entities.create_entity(uri, { owner = player_id })
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
      stacks_component:set_stacks((max_stacks and stacks_component:get_max_stacks()) or num_stacks or 1)
   end

   if crop_quality > 1 then
      self:_set_quality(product, self._crop)
   end

   return product
end

function AceHarvestCropAdjacent:_place_item_on_ground(player_id, item)
   -- place the item in a nearby location
   local pt = radiant.terrain.find_placement_point(self._location, 0, 2)
   radiant.terrain.place_entity(item, pt)
   stonehearth.inventory:get_inventory(player_id):add_item_if_not_full(item)
end

function AceHarvestCropAdjacent:_pickup_item(player_id, item)
   -- drop whatever they're currently carrying, then pick up the item
   radiant.entities.drop_carrying_nearby(self._entity)
   radiant.entities.pickup_item(self._entity, item)
   stonehearth.inventory:get_inventory(player_id):add_item_if_not_full(item)
end

function AceHarvestCropAdjacent:_harvest_megacrop_and_return(ai, player_id, crop_quality)
   local megacrop_data = radiant.entities.get_entity_data(self._crop, 'stonehearth_ace:megacrop') or {}
   local num_to_spawn = megacrop_data.num_to_spawn or 3
   local other_items = megacrop_data.other_items
   local pickup_new = other_items and megacrop_data.pickup_new ~= nil and megacrop_data.pickup_new
   
   -- spawn more of the product
   for i = 1, num_to_spawn do
      local product = self:_create_product(player_id, crop_quality, 1, true)
      if product then
         self:_place_item_on_ground(player_id, product)
      end
   end

   -- spawn other items
   if other_items then
      local new_items = {}
      for uri, count in pairs(other_items) do
         for i = 1, count do
            local item = self:_create_item(player_id, uri, crop_quality)
            table.insert(new_items, item)
         end
      end

      if #new_items > 0 then
         local drop_index = 1
         if pickup_new then
            self:_pickup_item(player_id, new_items[1])
            drop_index = 2
         end
   
         for i = drop_index, #new_items do
            self:_place_item_on_ground(player_id, new_items[i])
         end
      end
   end

   if megacrop_data.effect then
      -- if we're running an effect, go ahead and hide the crop so it's not sitting there while it's already been looted
      self._crop:get_component('render_info'):set_visible(false)

      ai:execute('stonehearth:run_effect', { effect = megacrop_data.effect })
   end

   -- if we picked up a new item, we don't want to continue the normal process
   -- of increasing the stacks on the carried item
   if pickup_new or megacrop_data.return_immediately then
      return true
   end
end

function AceHarvestCropAdjacent:_destroy_crop()
   if self._crop then
      -- if this crop should merely reset to an earlier stage, do that instead
      local crop = self._crop:get_component('stonehearth:crop')
      local stage = crop and crop:get_post_harvest_stage()
      if stage then
         self._crop:get_component('stonehearth:growing'):set_growth_stage(stage)
         -- reset visibility in case it was a megacrop that we hid
         self._crop:get_component('render_info'):set_visible(true)
      else
         radiant.entities.kill_entity(self._crop)
      end
      self._crop = nil
   end
end

return AceHarvestCropAdjacent
