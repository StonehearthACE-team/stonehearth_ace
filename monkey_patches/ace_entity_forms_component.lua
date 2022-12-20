local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local EntityFormsComponent = require 'stonehearth.components.entity_forms.entity_forms_component'
local AceEntityFormsComponent = class()

AceEntityFormsComponent._ace_old__ensure_iconic_form = EntityFormsComponent._ensure_iconic_form
function AceEntityFormsComponent:_ensure_iconic_form(post_load)
   self:_ensure_interaction_proxy()

   self:_ace_old__ensure_iconic_form(post_load)
end

function AceEntityFormsComponent:_destroy_interaction_proxy()
   if self._sv._interaction_proxy then
      if self._sv._interaction_proxy:is_valid() then
         radiant.entities.destroy_entity(self._sv._interaction_proxy)
      end
      self._sv._interaction_proxy = nil
   end
end

AceEntityFormsComponent._ace_old__cleanup_item_placement = EntityFormsComponent._cleanup_item_placement
function AceEntityFormsComponent:_cleanup_item_placement(is_destroy)
   if is_destroy then
      self:_destroy_interaction_proxy()
   end

   self:_ace_old__cleanup_item_placement(is_destroy)
end

AceEntityFormsComponent._ace_old_set_should_restock = EntityFormsComponent.set_should_restock
function AceEntityFormsComponent:set_should_restock(restock)
   self:_ace_old_set_should_restock(restock)

   radiant.events.trigger_async(self._entity, 'stonehearth_ace:reconsider_restock')
end

function AceEntityFormsComponent:_ensure_interaction_proxy()
   local entity = self._sv._interaction_proxy
   if not entity or not entity:is_valid() then
      -- check if a proxy should even be created
      -- only if both destination and region_collision_shape are specified, and they have different regions
      entity = nil   -- in case it was an invalid entity before
      local destination = self._entity:get_component('destination')
      local rcs = self._entity:get_component('region_collision_shape')
      if destination and rcs then
         if not csg_lib.are_same_shape_regions(destination:get_region():get(), rcs:get_region():get()) then
            entity = radiant.entities.create_entity('stonehearth_ace:manipulation:interaction_proxy')
            entity:add_component('stonehearth_ace:interaction_proxy'):set_entity(self._entity)
         end
      end

      self._sv._interaction_proxy = entity
   end
end

function AceEntityFormsComponent:get_interaction_proxy()
   return self._sv._interaction_proxy
end

-- ACE: pass the full entity into the place_ghost_entity function
function AceEntityFormsComponent:_place_item()
   self:set_should_restock(false) -- if we're gonna place this item, don't restock it. That would be rude

   local town = stonehearth.town:get_town(self._entity)

   assert(town)
   assert(self._sv.placement_info)
   assert(not self._sv.placement_ghost_entity)

   --ask the town to cancel any  other existing tasks on the root and the iconic
   town:remove_town_tasks_on_item(self._entity)
   town:remove_town_tasks_on_item(self:get_iconic_entity())

   --local uri = self._entity:get_uri()
   local player_id = radiant.entities.get_player_id(self._entity)
   local ghost, err = entity_forms.place_ghost_entity(self._entity, radiant.entities.get_item_quality(self._entity), player_id, self._sv.placement_info)

   assert(ghost, err)
   -- if we hide the undeploy ui, then we have to prevent cancelling the move as that hacks an undeploy
   if self._sv.hide_undeploy_ui then
      ghost:get_component('stonehearth:commands'):remove_command('stonehearth:commands:destroy_item')
   end
   self._sv.placement_ghost_entity = ghost
   radiant.events.trigger_async(self, 'stonehearth:entity:ghost_placed')

   local ghost_component = ghost:get_component('stonehearth:ghost_form')
   -- if root form item exists in world, then the item is placed and we are trying to move it
   local moving_placed_item = radiant.entities.exists_in_world(self._entity)
   ghost_component:request_place_item(moving_placed_item)

   local inventory = stonehearth.inventory:get_inventory(self._entity)
   if inventory then
      inventory:reevaluate_tracker_item(self._entity)
      inventory:reevaluate_tracker_item(self._sv.iconic_entity)
   end

   self:_start_placement_task()
end

-- ACE: make sure the ghost has the proper destination region
AceEntityFormsComponent._ace_old__start_placement_task = EntityFormsComponent._start_placement_task
function AceEntityFormsComponent:_start_placement_task()
   local rcs = self._entity:get_component('region_collision_shape')
   if rcs then
      local ghost_destination = self._sv.placement_ghost_entity:add_component('destination')
      if not ghost_destination:get_region() then
         ghost_destination:set_region(_radiant.sim.alloc_region3())
      end
      ghost_destination:get_region():modify(function(cursor)
            cursor:copy_region(rcs:get_region():get())
         end)
      ghost_destination:set_auto_update_adjacent(true)
      ghost_destination:set_adjacency_flags(_radiant.csg.AdjacencyFlags.ALL_EDGES)
   end

   self:_ace_old__start_placement_task()
end

function AceEntityFormsComponent:_reconsider_entity(reason)
   if radiant.is_server then
      stonehearth.ai:reconsider_entity(self._entity, reason .. ' (root)')
      stonehearth.ai:reconsider_entity(self._sv.iconic_entity, reason .. ' (iconic)')
      -- ACE: also reconsider the interaction proxy if there is one
      if self._sv._interaction_proxy then
         stonehearth.ai:reconsider_entity(self._sv._interaction_proxy, reason .. ' (proxy)')
      end
   end
end

return AceEntityFormsComponent
