local Point3 = _radiant.csg.Point3
local Entity = _radiant.om.Entity

local HarvestUndercropAdjacent = radiant.class()
HarvestUndercropAdjacent.name = 'harvest undercrop adjacent'
HarvestUndercropAdjacent.does = 'stonehearth_ace:harvest_undercrop_adjacent'
HarvestUndercropAdjacent.args = {
   underfield_layer = Entity,      -- the underfield the undercrop is in
   location = Point3,           -- the offset of the undercrop in the underfield
}
HarvestUndercropAdjacent.priority = 0

function HarvestUndercropAdjacent:start_thinking(ai, entity, args)
   self._log = ai:get_log()
   self._entity = entity
   self._spawn_count = self:_get_num_to_increment(entity)

   self._undercrop = args.underfield_layer:get_component('stonehearth_ace:grower_underfield_layer')
                                    :get_grower_underfield()
                                       :undercrop_at(args.location)

   if not self._undercrop or not self._undercrop:is_valid() then
      self._log:detail('no undercrop at %s (%s)', offset, tostring(self._undercrop))
      return
   end

   local carrying = ai.CURRENT.carrying
   if carrying then
      -- make sure it's the right undercrop...
      if not self:_is_same_undercrop(carrying, self._undercrop) then
         self._log:detail('not the same')
         return
      end
      -- make sure we can fit another load...
      if not self:_can_carry_more(entity, carrying) then
         self._log:detail('cannot carry more')
         return
      end
   end
   self._origin = radiant.entities.get_world_grid_location(args.underfield_layer)
   self._location = args.location
   self._destination = args.underfield_layer:get_component('destination')

   ai:protect_argument(self._undercrop)
   ai:set_think_output();
end

function HarvestUndercropAdjacent:_is_same_undercrop(entity, undercrop)
   local undercrop_component = undercrop:get_component('stonehearth_ace:undercrop')
   if not undercrop_component then
      self._log:detail('%s - %s has no undercrop component. false.', self._entity, undercrop)
      return false
   end
   if entity and entity:get_uri() ~= undercrop_component:get_product() then
      local iconic_component = entity:get_component('stonehearth:iconic_form')
      if not iconic_component or (iconic_component and iconic_component:get_root_entity():get_uri() ~= undercrop_component:get_product()) then
         self._log:detail('%s - %s ~= %s (%s)!', self._entity, entity, undercrop, undercrop_component:get_product())
         return false
      end
   end
   self._log:detail('%s - %s == %s!', self._entity, entity, undercrop)
   return true
end

function HarvestUndercropAdjacent:_harvest_one_time(ai, entity)
   assert(self._undercrop and self._undercrop:is_valid())

   local carrying = radiant.entities.get_carrying(entity)

   -- make sure we can pick up more of the undercrop
   if carrying then
      if not self:_can_carry_more(entity, carrying) then
         return false
      end
   end

   -- all good!  harvest once
   radiant.entities.turn_to_face(entity, self._undercrop)
   ai:execute('stonehearth:run_effect', { effect = 'fiddle' })

   -- bump up the count on the one we're carrying.
   if carrying then
      radiant.entities.increment_carrying(entity, self._spawn_count)
      return true
   end

   -- oops, not carrying!  stick something in our hands.
   local product_uri = self._undercrop:get_component('stonehearth_ace:undercrop')
                                    :get_product()

   if not product_uri then
      -- Product is nil likely because the undercrop has rotted in the underfield.
      -- We should just destroy it and keep going.
      return true
   end

   local product = radiant.entities.create_entity(product_uri, { owner = entity })
   local entity_forms = product:get_component('stonehearth:entity_forms')

   --If there is an entity_forms component, then you want to put the iconic version
   --in the grower's arms, not the actual entity (ie, if we had a chair undercrop)
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
   radiant.events.trigger(entity, 'stonehearth_ace:harvest_undercrop', {undercrop_uri = self._undercrop:get_uri()})
   self._log:detail('destroying undercrop %s', tostring(self._undercrop))
   return true
end

function HarvestUndercropAdjacent:run(ai, entity, args)
   -- it never hurts to be a little bit paranoid =)
   local carrying = radiant.entities.get_carrying(entity)
   if carrying and not self:_is_same_undercrop(carrying, self._undercrop) then
     ai:abort('not carrying the same type of undercrop')
   end

   self._log:detail('entering loop..')
   ai:unprotect_argument(self._undercrop)
   while self._undercrop and self._undercrop:is_valid() and self:_harvest_one_time(ai, entity) do
      radiant.events.trigger_async(entity, 'stonehearth_ace:harvest_one_undercrop', {undercrop_uri = self._undercrop:get_uri()})
      self:_unreserve_location()
      self:_destroy_undercrop()

      -- woot!  see if we can find another undercrop in
      self._log:detail('gimme more..')
      self:_move_to_next_available_undercrop(ai, entity, args)
   end

   self._log:detail('exited loop..')

   -- drop off what we've got for a worker to come suck up.
   local carrying = radiant.entities.get_carrying(entity)
   if carrying and not self:_can_carry_more(entity, carrying) then
      ai:execute('stonehearth:wander_within_leash', { radius = 5 })
      ai:execute('stonehearth:drop_carrying_now')
   end
end

function HarvestUndercropAdjacent:stop(ai, entity, args)
   self:_unreserve_location()
end

--By default, we produce 1 item stack per basket
function HarvestUndercropAdjacent:_get_num_to_increment(entity)
   local num_to_spawn = 1

   --If the this entity has the right perk, spawn more than one
   local job_component = entity:get_component('stonehearth:job')
   if job_component and job_component:curr_job_has_perk('grower_harvest_increase') then
      num_to_spawn = 2
   end

   return num_to_spawn
end

function HarvestUndercropAdjacent:_can_carry_more(entity, carrying)
   assert(self._spawn_count)

   local stacks_component = carrying:get_component('stonehearth:stacks')
   if not stacks_component or (stacks_component:get_stacks() + self._spawn_count >= stacks_component:get_max_stacks()) then
      return false
   end
   return true
end

function HarvestUndercropAdjacent:_destroy_undercrop()
   if self._undercrop then
      radiant.entities.kill_entity(self._undercrop)
      self._undercrop = nil
   end
end

function HarvestUndercropAdjacent:_unreserve_location()
   if self._location then
      if self._destination:is_valid() then
         local block = self._location - self._origin
         self._destination:get_reserved():modify(function(cursor)
            cursor:subtract_point(block)
         end)
      end
      self._location = nil
   end
end

function HarvestUndercropAdjacent:_move_to_next_available_undercrop(ai, entity, args)
   self._undercrop = nil

   -- see if there's a path to an unbuilt block on the same entity within 8 voxels
   local path = entity:get_component('stonehearth:pathfinder')
                           :find_path_to_entity_sync('find another undercrop to harvest',
                                                     args.underfield_layer,
                                                     8)

   if path then
      local location = path:get_destination_point_of_interest()
      local reserved = self._destination:get_reserved()

      -- Pull the undercrop out of that location
      self._undercrop = args.underfield_layer:get_component('stonehearth_ace:grower_underfield_layer')
                                 :get_grower_underfield()
                                    :undercrop_at(location)
      if not self._undercrop or not self._undercrop:is_valid() then
         return
      end

      -- reserve the undercrop so no one else grabs it
      local block = location - self._origin
      reserved:modify(function(cursor)
            cursor:add_point(block)
         end)

      -- remember the location so we can unreserve it later
      self._location = location

      -- follow the path.  this may go away for a while (which is why we had to reserve the
      -- block a few lines ago!)
      ai:execute('stonehearth:follow_path', { path = path })
   end
end

return HarvestUndercropAdjacent
