local Region3 = _radiant.csg.Region3

local VerticalPathingRegionComponent = class()

function VerticalPathingRegionComponent:activate()
   local vpr_component = self._entity:add_component('vertical_pathing_region')
   
   if not self._sv.set_region then
      vpr_component:set_region(_radiant.sim.alloc_region3())
      self._sv.set_region = true
      self.__saved_variables:mark_changed()

      local json = radiant.entities.get_json(self)
      if json and json.region then
         self:set_region(json.region)
      end
   end
end

function VerticalPathingRegionComponent:get_region()
   local vpr_component = self._entity:add_component('vertical_pathing_region')
   return vpr_component:get_region()
end

function VerticalPathingRegionComponent:set_region(region)
   local vpr_component = self._entity:add_component('vertical_pathing_region')
   vpr_component:get_region():modify(function(cursor)
      if radiant.util.is_a(region, Region3) then
         cursor:copy_region(region)
      elseif region then
         cursor:clear()
         for _, cube in ipairs(region or {}) do
            cursor:add_unique_cube(radiant.util.to_cube3(cube))
         end
      else
         cursor:clear()
      end
   end)
end

return VerticalPathingRegionComponent