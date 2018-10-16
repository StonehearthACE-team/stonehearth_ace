local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3

local FirepitComponent = class()
FirepitComponent.__classname = 'FirepitComponent'

local VISION_OFFSET = 1

function FirepitComponent:initialize()
   self._log = radiant.log.create_logger('firepit')
                              :set_entity(self._entity)

   self._sv.seats = nil
end

function FirepitComponent:restore()
   self._is_restore = true
end

function FirepitComponent:activate()
   --Trace the parent to figure out if it's added or not:
   self._parent_trace = self._entity:add_component('mob'):trace_parent('firepit added or removed')
                        :on_changed(function(parent_entity)
                              if not parent_entity then
                                 --we were just removed from the world
                                 self:_shutdown()
                              else
                                 --we were just added to the world
                                 self:_startup()
                              end
                           end)
end

function FirepitComponent:post_activate()
   if self._is_restore then
      self._parent_trace:push_object_state()
   end
end

function FirepitComponent:destroy()
   self._log:debug('destroy')

   if self._light_task then
      self._light_task:destroy()
      self._light_task = nil
   end

   --When the firepit is destroyed, destroy its seat entities too
   self:_shutdown()
end

function FirepitComponent:get_entity()
      return self._entity
end

function FirepitComponent:get_fuel_material()
   return 'wood resource'
end

--- If WE are added to the universe, register for events, etc/
function FirepitComponent:_on_entity_add(id, entity)
   if self._entity and self._entity:get_id() == id then
      self:_startup()
   end
end

function FirepitComponent:_on_entity_remove(id)
   if self._entity and self._entity:get_id() == id then
      self:_shutdown()
   end
end

function FirepitComponent:_startup()
   self._log:debug('creating alarms')

   local calendar_constants = stonehearth.calendar:get_constants()
   local event_times = calendar_constants.event_times
   local jitter = '+5m'

   if not self._sunrise_alarm then
      local sunrise_alarm_time = stonehearth.calendar:format_time(event_times.sunrise) .. jitter
      self._sunrise_alarm = stonehearth.calendar:set_alarm(sunrise_alarm_time, function()
            self:_start_or_stop_firepit()
         end)
   end
   if not self._sunset_alarm then
      local sunset_alarm_time = stonehearth.calendar:format_time(event_times.sunset_end) .. jitter
      self._sunset_alarm = stonehearth.calendar:set_alarm(sunset_alarm_time, function()
            self:_start_or_stop_firepit()
         end)
   end

   self:_start_or_stop_firepit()
end

--- Stop listening for events, destroy seats, terminate effects and tasks
-- Call when firepit is moving or being destroyed.
function FirepitComponent:_shutdown()
   self._log:debug('destroying alarms')

   if self._sunrise_alarm then
      self._sunrise_alarm:destroy()
      self._sunrise_alarm = nil
   end
   if self._sunset_alarm then
      self._sunset_alarm:destroy()
      self._sunset_alarm = nil
   end
   self:_extinguish()

   if self._sv.seats then
      for i, v in pairs(self._sv.seats) do
         self._log:debug('destroying firepit seat %s', tostring(v))
         radiant.entities.destroy_entity(v)
      end
   end
   self._sv.seats = nil
end

--- Reused between this and when we check to see if we should
-- light the fire after place.
function FirepitComponent:_start_or_stop_firepit()
   --Only light fires after dark
   local time_constants = stonehearth.calendar:get_constants()
   local curr_time = stonehearth.calendar:get_time_and_date()
   local should_light_fire = not stonehearth.calendar:is_daytime() or stonehearth.weather:is_dark_during_daytime()
   local is_lit = self:is_lit()

   self._log:debug('start or stop? (lit:%s should_light:%s)', tostring(is_lit), tostring(should_light_fire))

   --If we should already be lit (ie, from load, then just jump straight to light)
   if is_lit and should_light_fire then
      self:_light()
   elseif should_light_fire then
      self._log:detail('decided to light the fire!')
      self:_init_gather_wood_task()
   elseif not should_light_fire then
      self._log:detail('decided to put out the fire!')
      self:_extinguish()
   end
end

---Adds 8 seats around the firepit
--TODO: add a random element to the placement of the seats.
function FirepitComponent:_add_seats()
   self._log:debug('adding firepit seats')
   self._sv.seats = {}
   local firepit_loc = Point3(radiant.entities.get_world_grid_location(self._entity))
   self:_add_one_seat(1, Point3(firepit_loc.x + 5, firepit_loc.y, firepit_loc.z + 1))
   self:_add_one_seat(2, Point3(firepit_loc.x + -4, firepit_loc.y, firepit_loc.z))
   self:_add_one_seat(3, Point3(firepit_loc.x + 1, firepit_loc.y, firepit_loc.z + 5))
   self:_add_one_seat(4, Point3(firepit_loc.x + 1, firepit_loc.y, firepit_loc.z - 4))
   self:_add_one_seat(5, Point3(firepit_loc.x + 4, firepit_loc.y, firepit_loc.z + 4))
   self:_add_one_seat(6, Point3(firepit_loc.x + 4, firepit_loc.y, firepit_loc.z - 3))
   self:_add_one_seat(7, Point3(firepit_loc.x -3, firepit_loc.y, firepit_loc.z + 3))
   self:_add_one_seat(8, Point3(firepit_loc.x - 2, firepit_loc.y, firepit_loc.z - 3))

   self.__saved_variables:mark_changed()
end

function FirepitComponent:_add_one_seat(seat_number, location)
   -- Only place a seat in this location if it is standable
   local standable = radiant.terrain.is_standable(location)
   if standable then
      -- Check if there is an obstruction between the location and firepit
      -- Offset seat location y coord by 1 since that is usually the vision offset of the entities that sit at the firepit
      local line_of_sight = _physics:has_line_of_sight(self._entity, Point3(location.x, location.y + VISION_OFFSET, location.z))
      if not line_of_sight then
         return
      end
      local seat = radiant.entities.create_entity('stonehearth:decoration:firepit_seat', { owner = self._entity })
      local seat_comp = seat:get_component('stonehearth:center_of_attention_spot')
      seat_comp:add_to_center_of_attention(self._entity, seat_number)
      self._sv.seats[seat_number] = seat
      radiant.terrain.place_entity_at_exact_location(seat, location)
      self._log:spam('place firepit seat at %s', tostring(location))
   end
end

--- Create a worker task to gather wood
function FirepitComponent:_init_gather_wood_task()
   if self._light_task then
      self._light_task:destroy()
      self._light_task = nil
   end

   local town = stonehearth.town:get_town(self._entity)

   self._light_task = town:create_task_for_group('stonehearth:task_groups:placement','stonehearth:light_firepit', { firepit = self })
                                   :once()
                                   :start()
end

--- Returns whether or not the firepit is lit
function FirepitComponent:is_lit()
   local lamp_component = self._entity:get_component('stonehearth:lamp')
   if lamp_component then
      return lamp_component:is_lit()
   else
      return true  -- always-on
   end
end

--- Adds wood to the fire
-- External! Assumes we are lighting a cold firepit
-- Create a new entity instead of re-using the old one because if we wanted to do
-- that, we'd have to reparent the log to the fireplace.
-- Add the seats now, since we don't want the admire fire pf to start till the fire is lit.
function FirepitComponent:light()
   self:_light()
end

function FirepitComponent:_light()
   self._log:debug('lighting the fire')
   
   local lamp = self._entity:get('stonehearth:lamp')
   if lamp then
      lamp:light_on()
   end

   if not self._sv.seats then
      self:_add_seats()
   end

   -- reserve children in firepit
   local entity_container = self._entity:get_component('entity_container')

   local inventory = stonehearth.inventory:get_inventory(radiant.entities.get_player_id(self._entity))
   if entity_container and inventory then
      for id, child in entity_container:each_child() do
         inventory:remove_item(id)
      end
   end

   radiant.events.trigger_async(stonehearth, 'stonehearth:fire:lit', {
         lit = true,
         entity = self._entity,
         player_id = radiant.entities.get_player_id(self._entity),
      })

   self:_reconsider_firepit_and_seats()
   self.__saved_variables:mark_changed()
end

--- If there is wood, destroy it and extinguish the particles
function FirepitComponent:_extinguish()
   self._log:debug('extinguishing the fire')
   local was_lit = self:is_lit()
   
   local lamp = self._entity:get('stonehearth:lamp')
   if lamp then
      lamp:light_off()
   end

   local ec = self._entity:add_component('entity_container')

   while ec:num_children() > 0 do
	  local charcoal = radiant.entities.create_entity('stonehearth_ace:resources:coal:piece_of_charcoal')
      local id, child = ec:first_child()
      ec:remove_child(id)
      if child and child:is_valid() then
         radiant.entities.destroy_entity(child)
		 radiant.terrain.place_entity_at_exact_location(charcoal, self.entity)
		 
      end
   end

   if self._light_task then
      self._light_task:destroy()
      self._light_task = nil
   end
   
   if was_lit then
      radiant.events.trigger_async(stonehearth, 'stonehearth:fire:lit', { lit = false, player_id = radiant.entities.get_player_id(self._entity), entity = self._entity  })
   end

   self:_reconsider_firepit_and_seats()
   self.__saved_variables:mark_changed()
end

function FirepitComponent:_reconsider_firepit_and_seats()
   stonehearth.ai:reconsider_entity(self._entity, 'fire pit lit/extinguished')
   if self._sv.seats then
      for _, seat in pairs(self._sv.seats) do
         if seat and seat:is_valid() then
            stonehearth.ai:reconsider_entity(seat, 'fire pit lit/extinguished')
         end
      end
   end
end

return FirepitComponent
