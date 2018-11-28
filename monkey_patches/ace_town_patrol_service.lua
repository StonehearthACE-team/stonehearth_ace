local PatrollableObject = require 'services.server.town_patrol.patrollable_object'
local log = radiant.log.create_logger('town_patrol')
local TownPatrol = require 'stonehearth.services.server.town_patrol.town_patrol_service'

AceTownPatrol = class()

-- Conventions adopted in this class:
--   entity: a unit (like a footman)
--   object: everything else, typically something that can be patrolled

AceTownPatrol._old_initialize = TownPatrol.initialize
function AceTownPatrol:initialize()
	self:_old_initialize()

	if not self._sv._auto_patrol then
		self._sv._auto_patrol = {}
		self._sv._patrol_auto_backup = {}
		self.__saved_variables:mark_changed()
	end
end

AceTownPatrol._old_get_patrollable_objects = TownPatrol.get_patrollable_objects
function AceTownPatrol:get_patrollable_objects(entity, town_player_id)
   local ordered_objects = self:_old_get_patrollable_objects(entity, town_player_id)
   
   -- check to see if there are any 'patrol_banner' objects in here for the entity's combat party
   -- if so, start with the top such 'patrol_banner' and use it to find the rest in order
   -- otherwise, filter out all 'patrol_banner' objects from the list
   
   local party_member = entity:get_component('stonehearth:party_member')
   local party_comp
   if party_member then
      party_comp = party_member:get_party():get_component('stonehearth:party')
   else
      party_comp = entity:get_component('stonehearth:party')
   end
   
   local patrol_banners = {}
   local best_banner

   if party_comp then
      local party_id = party_comp:get_banner_variant()
      for _, object in ipairs(ordered_objects) do
         local pb_comp = object:get_banner()
         if pb_comp and pb_comp:get_party() == party_id then
            patrol_banners[object:get_id()] = object
            if not best_banner then
               best_banner = object
            end
         end
      end
   end

   if best_banner then
      local new_list = {}
      local check_list = {[best_banner:get_id()] = true}
      local cur_banner = best_banner

      while true do
         if not cur_banner then
            break
         end
         table.insert(new_list, cur_banner)

         local next_banner = cur_banner:get_banner():get_next_banner()
         if not next_banner then
            break
         end
         local next_id = next_banner:get_id()
         if check_list[next_id] then
            break
         end

         cur_banner = patrol_banners[next_id]
         if cur_banner then
            check_list[next_id] = true
         end
      end

      ordered_objects = new_list
   else
      for i = #ordered_objects, 1, -1 do
         local pb_comp = ordered_objects[i]:get_banner()
         if pb_comp then
            table.remove(ordered_objects, i)
         end
      end
   end

   return ordered_objects
end

function AceTownPatrol:_is_patrollable(object)
   if object == nil or not object:is_valid() then
      return false
   end

   local entity_data = radiant.entities.get_entity_data(object, 'stonehearth:town_patrol')
   return entity_data and (entity_data.auto_patrol == true or entity_data.manual_patrol == true)
end

-- Paul the Great: the trace callbacks aren't asynchronous, are they? do we have to worry about race conditions here?
function AceTownPatrol:_switch_to_manual(player_id)
	self._sv._auto_patrol[player_id] = false
	if not self._sv._auto_patrollable_objects then
		self._sv._auto_patrollable_objects = {}
	end
	self._sv._auto_patrollable_objects[player_id] = self:_get_patrollable_objects(player_id)
	self._sv._patrollable_objects[player_id] = {}

	-- saved variables will get set by the calling function, don't need to set them here
end

function AceTownPatrol:_switch_to_auto(player_id)
	self._sv._auto_patrol[player_id] = true
	self._sv._patrollable_objects[player_id] = self:_get_auto_patrollable_objects(player_id)

	-- saved variables will get set by the calling function, don't need to set them here
end

function AceTownPatrol:_add_to_patrol_list(object)
	local object_id = object:get_id()
	local patrollable_object = radiant.create_controller('stonehearth:patrollable_object', object)
	local player_id = radiant.entities.get_player_id(object)

	if player_id then
		local add_trigger = true
		local auto_patrol = self:_get_auto_patrol(player_id)
		-- first we have to determine if this is a manual patrol object, which have strict priority over auto patrol objects
		local manual = radiant.entities.get_entity_data(object, 'stonehearth:town_patrol').manual_patrol
		local player_patrollable_objects

		if not auto_patrol and not manual then
			-- if we're in manual mode but adding an auto object, we need to get our backup auto list
			player_patrollable_objects = self:_get_auto_patrollable_objects(player_id)
			self:__add_to_list(player_patrollable_objects, patrollable_object, object_id, player_id)

		else
			if manual and auto_patrol then
				-- we need to switch our main patrollable objects table to the manual one
				self:_switch_to_manual(player_id)
			end

			-- we're in auto_patrol and we're adding an auto_patrol object, or we're in manual and adding a manual one
			player_patrollable_objects = self:_get_patrollable_objects(player_id)
			self:__add_to_list(player_patrollable_objects, patrollable_object, object_id, player_id)

			-- we only care about triggering if it's part of our active patrol
			self:_trigger_patrol_route_available(player_id)
		end

		self._sv._object_to_player_map[object_id] = player_id
		self.__saved_variables:mark_changed()
	end

	-- trace all objects that are patrollable in case their ownership changes
	self:_add_player_id_trace(object)
end

function AceTownPatrol:__add_to_list(player_patrollable_objects, patrollable_object, object_id, player_id)
	player_patrollable_objects[object_id] = patrollable_object
	self.__saved_variables:mark_changed()
end

function AceTownPatrol:__remove_from_list(player_patrollable_objects, object_id)
	if player_patrollable_objects[object_id] then
        -- optionally cancel existing patrol routes here
        player_patrollable_objects[object_id]:destroy()
        player_patrollable_objects[object_id] = nil
    end
end

function AceTownPatrol:_remove_from_patrol_list(object_id)
   -- we don't have to check the mode, we can just try to remove from both auto and current
	local player_id = self._sv._object_to_player_map[object_id]
	self._sv._object_to_player_map[object_id] = nil

	if player_id then
		self:__remove_from_list(self:_get_patrollable_objects(player_id), object_id)
		self:__remove_from_list(self:_get_auto_patrollable_objects(player_id), object_id)

		-- if we're in manual mode and removed our last manual object, switch back to auto
		if not self:_get_auto_patrol(player_id) and not next(self._sv._patrollable_objects[player_id]) then
			self:_switch_to_auto(player_id)
		end
	end

	self:_remove_player_id_trace(object_id)

	self.__saved_variables:mark_changed()
end

function AceTownPatrol:_get_auto_patrollable_objects(player_id)
   if not self._sv._auto_patrollable_objects then
		self._sv._auto_patrollable_objects = {}
	end
   local player_patrollable_objects = self._sv._auto_patrollable_objects[player_id]

   if not player_patrollable_objects then
      player_patrollable_objects = {}
      self._sv._auto_patrollable_objects[player_id] = player_patrollable_objects
   end

   return player_patrollable_objects
end

function AceTownPatrol:_get_auto_patrol(player_id)
	if not self._sv._auto_patrol then
		self._sv._auto_patrol = {}
	end
	local auto_patrol = self._sv._auto_patrol[player_id]

	if auto_patrol == nil then
		self._sv._auto_patrol[player_id] = true
		auto_patrol = true
	end

	return auto_patrol
end

return AceTownPatrol
