local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local log = radiant.log.create_logger('crafting')

local DropCraftingIngredients = radiant.mods.require('stonehearth.ai.actions.drop_crafting_ingredients')
local AceDropCraftingIngredients = radiant.class()

-- Paul: I have to override this whole function just to pass the crafter along in the call to workshop_component:start_crafting_progress(...)
function AceDropCraftingIngredients:run(ai, entity, args)
   -- bump over so we're centered on the workbench.  teleport to the center of the cube
   -- in the adjacent that we're standing in.  this fixes the issues caused by misaligned
   -- crafters walking to 2x2 workshop.  just to be ultra paranoid, only do this if
   -- the area of the cube is 2.  (we don't want to jump to the very center of very long
   -- narrow adjacent cubes)
   local dst = args.target:get_component('destination')
   if dst then
      local adjacent = dst:get_adjacent()
      if adjacent then
         local offset = Point3(0.5, 0, 0.5)
         local entity_mob = entity:get_component('mob')
         local location = entity_mob:get_location()
                                       :translated(offset)

         local world_region = radiant.entities.local_to_world(adjacent:get(), args.target)
         for cube in world_region:each_cube() do
            if cube:get_area() == 2 and cube:contains(location) then
               local centroid = cube:get_centroid()
               local new_location = Point3(centroid.x, location.y, centroid.z)
                                          :translated(-offset)
               entity_mob:move_to(new_location)
            end
         end
      end
   end

   local crafter_component = entity:get_component('stonehearth:crafter')
   if crafter_component then
      -- Have to check for nil here because it's possible the crafter component is
      -- gone if we demote while this is running.
      local order = crafter_component:get_current_order()
      local workshop_component = args.target:get_component('stonehearth:workshop')
      local crafting_progress = workshop_component:start_crafting_progress(order, entity) -- Paul: this is the only line changed
      if not crafting_progress then
         ai:abort('no crafting progress for order')  -- TODO: Figure out exactly when this can happen.
      end
      crafting_progress:add_ingredient_leases(self._item_leases)

      crafter_component:set_current_workshop(args.target)

      local drop_offset
      local container_entity_data = radiant.entities.get_entity_data(args.target, 'stonehearth:table')
      if container_entity_data then
         local offset = container_entity_data['drop_offset']
         if offset then
            local facing = math.floor(radiant.entities.get_facing(args.target) + 0.5)
            local offset = Point3(offset.x, offset.y, offset.z)
            drop_offset = offset:rotated(facing)
         end
      end

      local max_to_drop = order:get_max_ingredients_to_animate_dropping()
      local num_dropped = 0
      while true do
         local item = crafter_component:remove_first_item()
         if not item then
            return
         end

         if item:is_valid() then
            --Should be OK because this action starts with drop carrying now, but just in case!
            assert(not radiant.entities.is_carrying(entity))

            -- if we've already dropped a lot of items, just instantly dump the rest so we're not here all day
            if num_dropped > max_to_drop then
               radiant.entities.put_carrying_into_entity(entity, args.target)
               if drop_offset then
                  item:add_component('mob'):move_to(drop_offset)
               end
            else
               radiant.entities.pickup_item(entity, item)
               --Feeling kind of bad about this; this doesn't block now but what if it does later?
               ai:execute('stonehearth:drop_carrying_into_entity_adjacent', { entity = args.target })
               num_dropped = num_dropped + 1
            end
         else
            log:warning('Crafting ingredient destroyed before dropping onto workshop. Allowing craft to continue.')
         end
      end
   end
end

return AceDropCraftingIngredients
