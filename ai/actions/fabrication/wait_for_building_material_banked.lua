local Entity = _radiant.om.Entity
local WaitForBuildingMaterialBanked = radiant.class()

WaitForBuildingMaterialBanked.name = 'wait for a construction material to be banked at a building'
WaitForBuildingMaterialBanked.does = 'stonehearth_ace:wait_for_building_material_banked'
WaitForBuildingMaterialBanked.args = {
   building = Entity,
   material = 'string',
}
WaitForBuildingMaterialBanked.priority = 0.0

function WaitForBuildingMaterialBanked:start_thinking(ai, entity, args)
   local building_comp = args.building:get_component('stonehearth:build2:building')
   if building_comp then
      if args.material == stonehearth.constants.construction.NO_MATERIAL or building_comp:has_banked_resource(args.material) then
         ai:set_think_output({})
      else
         self._resource_banked_listener = radiant.events.listen(args.building, 'stonehearth_ace:material_resource_banked', function(material)
            if material == args.material then
               ai:set_think_output({})
            end
         end)
      end
   else
      ai:reject('not a valid building')
   end
end

function WaitForBuildingMaterialBanked:stop_thinking(ai, entity, args)
   self:_destroy_listeners()
end

function WaitForBuildingMaterialBanked:destroy()
   self:_destroy_listeners()
end

function WaitForBuildingMaterialBanked:_destroy_listeners()
   if self._resource_banked_listener then
      self._resource_banked_listener:destroy()
      self._resource_banked_listener = nil
   end
end

return WaitForBuildingMaterialBanked
