local VerticalPathingRegionComponent = class()

function VerticalPathingRegionComponent:activate()
   local vpr_component = self._entity:add_component('vertical_pathing_region')
   
   if not self._sv.set_region then
      vpr_component:set_region(_radiant.sim.alloc_region3())
      self._sv.set_region = true
      self.__saved_variables:mark_changed()
   end

   local json = radiant.entities.get_json(self)
   vpr_component:get_region():modify(function(r)
      r:clear()
      for _, cube in ipairs(json.region or {}) do
         r:add_unique_cube(radiant.util.to_cube3(cube))
      end
   end)
end

return VerticalPathingRegionComponent