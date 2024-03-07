-- when added, apply a movement modifier shape modifier and/or nav grid modifier to the entity
-- only effects entities with movement_modifier_shape component
-- tries to reset it to original value when removed; be careful so only one such buff is applied at a time

local Region3 = _radiant.csg.Region3

local ApplyMMS = class()

function ApplyMMS:on_buff_added(entity, buff)
   self._tuning = buff:get_json().script_info
   self._entity = entity

   local mms = entity:get_component('movement_modifier_shape')
   if mms then
      if self._tuning.modifier then
         mms:set_modifier(self._tuning.modifier)
      end
      if self._tuning.nav_preference_modifier then
         mms:set_nav_preference_modifier(self._tuning.nav_preference_modifier)
      end
      if self._tuning.region then
         if not mms:get_region() then
            mms:set_region(_radiant.sim.alloc_region3())
         end
         local r = Region3()
         r:load(self._tuning.region)
         mms:get_region():modify(function(cursor)
            cursor:copy_region(r)
         end)
      end
   end
end

function ApplyMMS:on_buff_removed(entity, buff)
   local mms = entity:get_component('movement_modifier_shape')
   if mms then
      local component_data = radiant.entities.get_component_data(entity, 'movement_modifier_shape')
      if component_data then
         if self._tuning.modifier then
            mms:set_modifier(component_data.modifier or 0)
         end
         if self._tuning.nav_preference_modifier then
            mms:set_nav_preference_modifier(component_data.nav_preference_modifier or 0)
         end
         if self._tuning.region then
            local r = Region3()
            if component_data.region then
               r:load(component_data.region)
            end
            mms:get_region():modify(function(cursor)
               cursor:copy_region(r)
            end)
         end
      end
   end
end

return ApplyMMS
