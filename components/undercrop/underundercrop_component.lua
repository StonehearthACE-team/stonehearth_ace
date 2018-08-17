--[[
   Every time the undercrop grows, update its resource node resource. More mature undercrops
   yield better resources.
]]
local UndercropComponent = class()

function UndercropComponent:initialize()
   -- Initializing save variables
   self._sv.harvestable = false
   self._sv.stage = nil
   self._sv.product = nil
   self._sv._underfield = nil
   self._sv._underfield_offset_x = 0
   self._sv._underfield_offset_y = 0

   local json = radiant.entities.get_json(self)
   self._resource_pairings = json.resource_pairings
   self._harvest_threshhold = json.harvest_threshhold
end

function UndercropComponent:restore()
   local growing_component = self._entity:get_component('stonehearth:growing')
   if growing_component then
      local stage = growing_component:get_current_stage_name()
      if stage ~= self._sv.stage then
         -- If stages are mismatched somehow, fix it up.
         -- There was a carrot undercrop whose stage got mixed up somehow
         -- Likely due to a growing component listener firing when listener was not yet registered -yshan 3/2/2016
         local e = {}
         e.stage = stage
         e.finished = growing_component:is_finished()
         self:_on_grow_period(e)
      end
   end
end

function UndercropComponent:activate()
   if self._entity:get_component('stonehearth:growing') then
      self._growing_listener = radiant.events.listen(self._entity, 'stonehearth:growing', self, self._on_grow_period)
   end
end

function UndercropComponent:post_activate()
   if self._sv.harvestable and self._sv._underfield then
      self:_notify_harvestable()
   end
end

function UndercropComponent:set_underfield(underfield, x, y)
   self._sv._underfield = underfield
   self._sv._underfield_offset_x = x
   self._sv._underfield_offset_y = y
end

function UndercropComponent:get_underfield()
   return self._sv._underfield
end

function UndercropComponent:get_underfield_offset()
   return self._sv._underfield_offset_x, self._sv._underfield_offset_y
end

function UndercropComponent:get_product()
   return self._sv.product
end

function UndercropComponent:destroy()
   if self._sv._underfield then
      self._sv._underfield:notify_undercrop_destroyed(self._sv._underfield_offset_x, self._sv._underfield_offset_y)
      self._sv._underfield = nil
   end
   if self._growing_listener then
      self._growing_listener:destroy()
      self._growing_listener = nil
   end

   if self._game_loaded_listener then
      self._game_loaded_listener:destroy()
      self._game_loaded_listener = nil
   end
end

--- As we grow, change the resources we yield and, if appropriate, command harvest
function UndercropComponent:_on_grow_period(e)
   self._sv.stage = e.stage
   if e.stage then
      local resource_pairing_uri = self._resource_pairings[self._sv.stage]
      if resource_pairing_uri then
         if resource_pairing_uri == "" then
            resource_pairing_uri = nil
         end
         self._sv.product = resource_pairing_uri
      end
      if self._sv.stage == self._harvest_threshhold and self._sv._underfield then
         self._sv.harvestable = true
         self:_notify_harvestable()
      end
   end
   if e.finished then
      --TODO: is growth ever really complete? Design the difference between "can't continue" and "growth complete"
      if self._growing_listener then
         self._growing_listener:destroy()
         self._growing_listener = nil
      end
   end
   self.__saved_variables:mark_changed()
end

--- Returns true if it's time to harvest, false otherwise
function UndercropComponent:is_harvestable()
   return self._sv.harvestable
end

function UndercropComponent:_notify_harvestable()
   radiant.assert(self._sv._underfield, 'undercrop %s has no underfield!', self._entity)
   self._sv._underfield:notify_undercrop_harvestable(self._sv._underfield_offset_x, self._sv._underfield_offset_y)
end

return UndercropComponent
