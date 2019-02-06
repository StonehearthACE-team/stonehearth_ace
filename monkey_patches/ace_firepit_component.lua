local FirepitComponent = require 'stonehearth.components.firepit.firepit_component'
local AceFirepitComponent = class()
local Point3 = _radiant.csg.Point3
local EMBER_URI = 'stonehearth_ace:decoration:ember'
local EMBER_CHARCOAL_URI = 'stonehearth_ace:decoration:ember_charcoal'
local CHARCOAL_URI = 'stonehearth_ace:resources:coal:piece_of_charcoal'

function AceFirepitComponent:get_fuel_material()
   return 'low_fuel'
end

AceFirepitComponent._ace_old_activate = FirepitComponent.activate
function AceFirepitComponent:activate()
   self._json = radiant.entities.get_json(self) or {}
   self._ember_uri = self._json.ember_uri or EMBER_URI
   self._ember_charcoal_uri = self._json.ember_charcoal_uri or EMBER_CHARCOAL_URI
   self._charcoal_uri = self._json.charcoal_uri or CHARCOAL_URI
   self._allow_charcoal = (self._json.allow_charcoal ~= false)
   self._transform_residue_time = self._json.transform_residue_time or 'midday'
   self._transform_residue_jitter = '+' .. (self._json.transform_residue_jitter or '2h')

   self:_ace_old_activate()
end

AceFirepitComponent._ace_old_startup = FirepitComponent._startup
function AceFirepitComponent:_startup()
   self:_ace_old_startup()

   if not self._transform_residue_timer then
      local calendar_constants = stonehearth.calendar:get_constants()
      local event_times = calendar_constants.event_times
      local event_time = calendar_constants.event_times[self._transform_residue_time] or self._transform_residue_time
      local formatted_time = stonehearth.calendar:format_time(event_time) .. self._transform_residue_jitter
      self._transform_residue_timer = stonehearth.calendar:set_alarm(formatted_time, function()
            self:_transform_residue()
         end)
   end
end

AceFirepitComponent._ace_old_shutdown = FirepitComponent._shutdown
function AceFirepitComponent:_shutdown()
   if self._transform_residue_timer then
      self._transform_residue_timer:destroy()
      self._transform_residue_timer = nil
   end
   
   self:_ace_old_shutdown()

end

function AceFirepitComponent:_transform_residue()
   local is_lit = self:is_lit()
   if is_lit then
	   return
   end
   
   local entity_container = self._entity:get_component('entity_container')
   
   if entity_container then
      local player_id = radiant.entities.get_player_id(self._entity)
      
      for id, child in entity_container:each_child() do
         if child and child:is_valid() and child:get_uri() == self._charcoal_uri then
            return
         elseif child and child:is_valid() and child:get_uri() == self._ember_charcoal_uri then
            entity_container:remove_child(id)
            radiant.entities.destroy_entity(child)
            self:_create_residue(self._charcoal_uri)
		    self._log:debug('transforming a charcoal ember into charcoal...')			
         elseif child and child:is_valid() and child:get_uri() == self._ember_uri then
            entity_container:remove_child(id)
            radiant.entities.destroy_entity(child)
         end
      end
   end
end

AceFirepitComponent._ace_old_extinguish = FirepitComponent._extinguish
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
   
   self:_ace_old_extinguish()

   if was_lit then
      if is_wood then
		 if self._allow_charcoal then
             self:_create_residue(self._ember_charcoal_uri)
             self._log:debug('creating a charcoal ember...')
		 else
		 self:_create_residue(self._ember_uri)
         self._log:debug('charcoal not allowed, creating common embers...')
		 end
      elseif is_low_fuel then
         self:_create_residue(self._ember_uri)
         self._log:debug('creating common embers...')
      end
   end
end

function AceFirepitComponent:_create_residue(residue_uri)
   local player_id = radiant.entities.get_player_id(self._entity)
   local residue = radiant.entities.create_entity(residue_uri, { owner = player_id })
   local entity_container = self._entity:get_component('entity_container')
   local entity_data = radiant.entities.get_entity_data(self._entity, 'stonehearth:table') or nil
   local drop_offset = nil
   
   entity_container:add_child(residue)
   
   if entity_data then
	  local offset = entity_data['drop_offset']
	  if offset then
         local facing = residue:get_component('mob')
										:get_facing()
         local offset = Point3(offset.x, offset.y, offset.z)
		 local drop_offset = offset:rotated(facing)
		 local mob = residue:add_component('mob')
		 mob:move_to(drop_offset)
	     end
   end
   
end

function AceFirepitComponent:_retrieve_charcoal()
   local entity_container = self._entity:get_component('entity_container')
   local location = radiant.entities.get_world_grid_location(self._entity)

   for id, child in entity_container:each_child() do
      if child and child:is_valid() and child:get_uri() == self._charcoal_uri then
         entity_container:remove_child(id)
         location = radiant.terrain.find_placement_point(location, 0, 3)
         radiant.terrain.place_entity(child, location)
      elseif child and child:is_valid() and child:get_uri() == self._ember_charcoal_uri then
         entity_container:remove_child(id)
         radiant.entities.destroy_entity(child)
      elseif child and child:is_valid() and child:get_uri() == self._ember_uri then
         entity_container:remove_child(id)
         radiant.entities.destroy_entity(child)
      end
   end
end

return AceFirepitComponent