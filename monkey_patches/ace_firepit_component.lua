local FirepitComponent = require 'stonehearth.components.firepit.firepit_component'
local AceFirepitComponent = class()
local Point3 = _radiant.csg.Point3
local EMBER_URI = 'stonehearth_ace:decoration:ember'
local EMBER_CHARCOAL_URI = 'stonehearth_ace:decoration:ember_charcoal'
local CHARCOAL_URI = 'stonehearth_ace:resources:coal:piece_of_charcoal'
local DEFAULT_FUEL = 'low_fuel'
local VISION_OFFSET = 1

AceFirepitComponent._ace_old_activate = FirepitComponent.activate
function AceFirepitComponent:activate()
   self._json = radiant.entities.get_json(self) or {}
   self._fuel = self._json.fuel or DEFAULT_FUEL
   self._ember_uri = self._json.ember_uri or EMBER_URI
   self._ember_charcoal_uri = self._json.ember_charcoal_uri or EMBER_CHARCOAL_URI
   self._charcoal_uri = self._json.charcoal_uri or CHARCOAL_URI
   self._allow_charcoal = (self._json.allow_charcoal ~= false)
   self._transform_residue_time = self._json.transform_residue_time or 'midday'
   self._transform_residue_jitter = '+' .. (self._json.transform_residue_jitter or '2h')
   self._buff_source = self._json.buff_source or false
   self._create_seats = (self._json.create_seats ~= false)
   if self._buff_source then
      self._buff = self._json.buff or 'stonehearth_ace:buffs:weather:warmth_source'
   end

   self:_ace_old_activate()
end

function AceFirepitComponent:get_fuel_material()
   return self._fuel
end

-- This entire function needs to be replaced for the seat creation conditional :(
function AceFirepitComponent:_light()
   self._log:debug('lighting the fire')

   if self._buff_source then
      local buff = self._buff
      radiant.entities.add_buff(self._entity, buff)
   end
   
   local lamp = self._entity:get('stonehearth:lamp')
   if lamp then
      lamp:light_on()
   end

   if not self._sv.seats and self._create_seats then
      self:_add_seats()
   end

   -- reserve children in firepit
   local entity_container = self._entity:get_component('entity_container')

   local player_id = radiant.entities.get_player_id(self._entity)
   local inventory = stonehearth.inventory:get_inventory(player_id)
   if entity_container and inventory then
      for id, child in entity_container:each_child() do
         local owner = stonehearth.ai:get_ai_lease_owner(child)
         if owner then
            stonehearth.ai:release_ai_lease(child, owner, nil, player_id)
         end
         child:add_component('stonehearth:lease'):acquire(stonehearth.constants.ai.RESERVATION_LEASE_NAME, self._entity, true)
         inventory:remove_item(id)
      end
   end

   radiant.events.trigger_async(stonehearth, 'stonehearth:fire:lit', {
         lit = true,
         entity = self._entity,
         player_id = player_id,
      })

   self:_reconsider_firepit_and_seats()
   self.__saved_variables:mark_changed()
end

-- a little patch to allow firepits that are sunk 1 voxel into the ground to also create seats
AceFirepitComponent._ace_old__add_one_seat = FirepitComponent._add_one_seat
function AceFirepitComponent:_add_one_seat(seat_number, location)
   -- check if there are any non-iconic entities with iconic forms (e.g., "placed" objects) in this location
   -- if so, don't try to make a seat 1 higher, because then it could be on top of a table or whatever
   -- if that entity should allow people to sit on it, it should handle that itself
   local has_blocking_entity = false
   for id, entity in pairs(radiant.terrain.get_entities_at_point(location)) do
      local entity_forms = entity:get_component('stonehearth:entity_forms')
      if entity_forms and entity_forms:get_iconic_entity() then
         self._log:spam('firepit seat location %s has potentially blocking entity %s, not trying at higher location', tostring(location), entity)
         has_blocking_entity = true
         break
      end
   end

   local higher_location = Point3(location.x, location.y + 1, location.z)
   if not has_blocking_entity and radiant.terrain.is_standable(higher_location) then
      self:_ace_old__add_one_seat(seat_number, higher_location)
   else
      -- still try even if there's a blocking_entity, because it might not have solid collision and still be a standable spot
      self:_ace_old__add_one_seat(seat_number, location)
   end
end

AceFirepitComponent._ace_old__startup = FirepitComponent._startup
function AceFirepitComponent:_startup()
   self:_ace_old__startup()

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
            radiant.entities.destroy_entity(child)
            self:_create_residue(self._charcoal_uri, false)
            self._log:debug('transforming a charcoal ember into charcoal...')            
         elseif child and child:is_valid() and child:get_uri() == self._ember_uri then
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
   local is_fuel = false
   
   for id, child in ec:each_child() do
      if radiant.entities.is_material(child, 'wood resource') then
         is_wood = true
         break
      elseif radiant.entities.is_material(child, self._fuel) then
         is_fuel = true
         break 
      end
   end
   
   self:_ace_old_extinguish()

   if was_lit then
      if self._buff_source then
         local buff = self._buff
         radiant.entities.remove_buff(self._entity, buff)
      end
      if is_wood then
         if self._allow_charcoal then
            self:_create_residue(self._ember_charcoal_uri, true)
            self._log:debug('creating a charcoal ember...')
         else
            self:_create_residue(self._ember_uri, true)
            self._log:debug('charcoal not allowed, creating common embers...')
         end
      elseif is_fuel then
         self:_create_residue(self._ember_uri, true)
         self._log:debug('creating common embers...')
      end
   end
end

function AceFirepitComponent:_create_residue(residue_uri, reserve)
   local player_id = radiant.entities.get_player_id(self._entity)
   local residue = radiant.entities.create_entity(residue_uri, { owner = player_id })
   local entity_container = self._entity:get_component('entity_container')
   local entity_data = radiant.entities.get_entity_data(self._entity, 'stonehearth:table')
   local drop_offset = nil
   
   if reserve then
      residue:add_component('stonehearth:lease'):acquire(stonehearth.constants.ai.RESERVATION_LEASE_NAME, self._entity, true)
   end
   entity_container:add_child(residue)
   
   if entity_data then
      local offset = entity_data['drop_offset']
      if offset then
         local facing = radiant.entities.get_facing(self._entity)
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
      if child and child:is_valid() and child:get_uri() == self._charcoal_uri and self._allow_charcoal then
         location = radiant.terrain.find_placement_point(location, 0, 3)
         radiant.terrain.place_entity(child, location)
         child:add_component('stonehearth:lease'):release(stonehearth.constants.ai.RESERVATION_LEASE_NAME, self._entity)
      elseif child and child:is_valid() and child:get_uri() == self._ember_charcoal_uri then
         radiant.entities.destroy_entity(child)
      elseif child and child:is_valid() and child:get_uri() == self._ember_uri then
         radiant.entities.destroy_entity(child)
      end
   end
end

function AceFirepitComponent:get_seats()
   return self._sv.seats
end

function AceFirepitComponent:has_active_conversation()
   return self._conversation ~= nil
end

function AceFirepitComponent:try_start_conversation(initiator)
   if self:has_active_conversation() then
      return false
   end

   local seats = self._sv.seats
   if not seats then
      return false
   end

   -- check each seat to see if it has someone seated in it (need to patch center_of_attention_spot_component and admire_fire_adjacent for that)
   -- add any non-initiators to the list; if there's more than one, start a conversation
   -- have to add sitting conversation animations to hearthlings before we can do this
   local participants = {initiator}
   for _, seat in pairs(seats) do

   end
end

return AceFirepitComponent