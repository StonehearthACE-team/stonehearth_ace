local csg_lib = require 'stonehearth.lib.csg.csg_lib'

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

return AceEntityFormsComponent
