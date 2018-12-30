local FirepitComponent = require 'stonehearth.components.firepit.firepit_component'
local AceFirepitComponent = class()
local EMBER_URI = 'stonehearth_ace:decoration:ember'
local CHARCOAL_EMBER_URI = 'stonehearth_ace:decoration:ember_charcoal'
local CHARCOAL_URI = 'stonehearth_ace:resources:coal:piece_of_charcoal'

function AceFirepitComponent:get_fuel_material()
   return 'low_fuel'
end

AceFirepitComponent._old_startup = FirepitComponent._startup
function AceFirepitComponent:_startup()
   local calendar_constants = stonehearth.calendar:get_constants()
   local event_times = calendar_constants.event_times
   local long_jitter = '+2h'
   
   self:_old_startup()

   if not self._midday_alarm then
      local midday_alarm_time = stonehearth.calendar:format_time(event_times.midday) .. long_jitter
      self._midday_alarm = stonehearth.calendar:set_alarm(midday_alarm_time, function()
            self:_transform_residue()
         end)
   end
end

AceFirepitComponent._old_shutdown = FirepitComponent._shutdown
function AceFirepitComponent:_shutdown()
   if self._midday_alarm then
      self._midday_alarm:destroy()
      self._midday_alarm = nil
   end
   
   self:_old_shutdown()

end

function AceFirepitComponent:_transform_residue()
   local entity_container = self._entity:get_component('entity_container')
   local player_id = radiant.entities.get_player_id(self._entity)
   local is_lit = self:is_lit()

   if is_lit then
	  return
   end
   
   for id, child in entity_container:each_child() do
      if child and child:is_valid() and child:get_uri() == CHARCOAL_URI then
         return
      elseif child and child:is_valid() and child:get_uri() == CHARCOAL_EMBER_URI then
	     local charcoal = radiant.entities.create_entity(CHARCOAL_URI, { owner = player_id })
		 entity_container:remove_child(id)
		 radiant.entities.destroy_entity(child)
		 entity_container:add_child(charcoal)		 
      elseif child and child:is_valid() and child:get_uri() == EMBER_URI then
		 entity_container:remove_child(id)
		 radiant.entities.destroy_entity(child)
      end
   end
end

AceFirepitComponent._old_extinguish = FirepitComponent._extinguish
function AceFirepitComponent:_extinguish()
   local was_lit = self:is_lit()
   local ec = self._entity:add_component('entity_container')
   local is_wood = false
   local is_low_fuel = false
   
   for id, child in ec:each_child() do
      if radiant.entities.is_material(child, 'wood resource') then
         is_wood = true
         break
      elseif radiant.entities.is_material(child, 'low_fuel') then
		 is_low_fuel = true
		 break 
	  end
   end
   
   self:_old_extinguish()

   if was_lit then
	  if is_wood then
		self:_create_residue(CHARCOAL_EMBER_URI)
		self._log:debug('creating a charcoal...')
	  elseif is_low_fuel then
		self:_create_residue(EMBER_URI)
		self._log:debug('creating common embers...')
      end
   end
end

function AceFirepitComponent:_create_residue(residue_uri)
   local player_id = radiant.entities.get_player_id(self._entity)
   local residue = radiant.entities.create_entity(residue_uri, { owner = player_id })
   local entity_container = self._entity:get_component('entity_container')
   entity_container:add_child(residue)
end

function AceFirepitComponent:_retrieve_charcoal()
   local entity_container = self._entity:get_component('entity_container')
   local location = radiant.entities.get_world_grid_location(self._entity)

   for id, child in entity_container:each_child() do
      if child and child:is_valid() and child:get_uri() == CHARCOAL_URI then
         entity_container:remove_child(id)
         location = radiant.terrain.find_placement_point(location, 0, 3)
         radiant.terrain.place_entity(child, location)
      elseif child and child:is_valid() and child:get_uri() == CHARCOAL_EMBER_URI then
		 entity_container:remove_child(id)
		 radiant.entities.destroy_entity(child)
      elseif child and child:is_valid() and child:get_uri() == EMBER_URI then
		 entity_container:remove_child(id)
		 radiant.entities.destroy_entity(child)
      end
   end
end

return AceFirepitComponent