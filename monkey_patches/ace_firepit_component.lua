local FirepitComponent = require 'stonehearth.components.firepit.firepit_component'
local AceFirepitComponent = class()
local CHARCOAL_URI = 'stonehearth_ace:resources:coal:piece_of_charcoal'

function AceFirepitComponent:get_fuel_material()
   return 'low_fuel resource'
end

AceFirepitComponent._old_extinguish = FirepitComponent._extinguish
function AceFirepitComponent:_extinguish()
   local was_lit = self:is_lit()
   local ec = self._entity:add_component('entity_container')
   local is_wood = false
   local material = self:get_fuel_material()
   
   for id, child in ec:each_child() do
      if radiant.entities.is_material(child, material) then
         is_wood = true
         break
      end
   end
   
   self:_old_extinguish()

   if was_lit and is_wood then
      self:_create_charcoal()
	   self._log:debug('creating a charcoal...')
   end
end

function AceFirepitComponent:_create_charcoal()
   local player_id = radiant.entities.get_player_id(self._entity)
   local charcoal = radiant.entities.create_entity(CHARCOAL_URI, { owner = player_id })
   local entity_container = self._entity:get_component('entity_container')
   entity_container:add_child(charcoal)
end

function AceFirepitComponent:_retrieve_charcoal()
   local entity_container = self._entity:get_component('entity_container')
   local location = radiant.entities.get_world_grid_location(self._entity)

   for id, child in entity_container:each_child() do
      if child and child:is_valid() and child:get_uri() == CHARCOAL_URI then
         entity_container:remove_child(id)
         location = radiant.terrain.find_placement_point(location, 0, 3)
         radiant.terrain.place_entity(child, location)
      end
   end
end

return AceFirepitComponent