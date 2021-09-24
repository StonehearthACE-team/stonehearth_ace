--[[
   a middleman interface between water "sources" (water components, water containers, water sponges)
   and the water channel system that links and transfers water (e.g., via waterfalls)
]]

local WaterSourceComponent = class()

function WaterSourceComponent:activate()
   self._water_component = self._entity:get_component('stonehearth:water')
   self._water_sponge_component = self._entity:get_component('stonehearth_ace:water_sponge')
end

function WaterSourceComponent:get_num_oscillations()
   if self._water_component then
      return self._water_component:get_num_oscillations()
   else
      return 0
   end
end

function WaterSourceComponent:get_water_level()
   if self._water_component then
      return self._water_component:get_water_level()
   else
      local location = radiant.entities.get_world_grid_location(self._entity)
      return location and location.y + 0.2 or 0
   end
end

function WaterSourceComponent:remove_point_from_region(point)
   if self._water_component then
      self._water_component:remove_point_from_region(point)
   end
end

-- clamp is unused by non-body water sources
function WaterSourceComponent:remove_water(volume, clamp, mark_changed)
   if self._water_component then
      return self._water_component:remove_water(volume, clamp, mark_changed)
   elseif self._water_sponge_component then
      return self._water_sponge_component:remove_water(volume, nil, mark_changed)
   end

   while volume > 0 do
      local residual = self:_remove_height(volume)
      if residual == volume then
         -- remove height was not successful
         break
      end
      volume = residual
      if clamp then
         break
      end
   end
   return volume
end

return WaterSourceComponent
