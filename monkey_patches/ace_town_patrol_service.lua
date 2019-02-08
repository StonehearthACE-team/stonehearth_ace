local PatrollableObject = require 'services.server.town_patrol.patrollable_object'
local log = radiant.log.create_logger('town_patrol')
local TownPatrol = require 'stonehearth.services.server.town_patrol.town_patrol_service'

AceTownPatrol = class()

function AceTownPatrol:get_patrol_banners(player_id)
   if not self._sv.patrol_banners then
		self._sv.patrol_banners = {}
	end
   local banners = self._sv.patrol_banners[player_id]
   if not banners then
      banners = radiant.create_controller('stonehearth_ace:player_patrol_banners', player_id)
      self._sv.patrol_banners[player_id] = banners
      self.__saved_variables:mark_changed()
   end
   return banners
end

function AceTownPatrol:get_patrollable_objects(entity, town_player_id)
   -- check to see if there are any 'patrol_banner' objects in here for the entity's combat party
   -- if so, start with the top such 'patrol_banner' and use it to find the rest in order
   -- otherwise, filter out all 'patrol_banner' objects from the list
   
   local party_member = entity:get_component('stonehearth:party_member')
   local party_comp
   if party_member then
      local party = party_member:get_party() 
      party_comp = party and party:get_component('stonehearth:party')
   else
      party_comp = entity:get_component('stonehearth:party')
   end
   
   if party_comp then
      local party_id = party_comp:get_banner_variant()

      if party_id then
         local new_list = self:get_patrol_banners(town_player_id):get_ordered_banners_by_party(party_id)
         if new_list and #new_list > 0 then
            local location = radiant.entities.get_world_location(entity)

            if location then
               local sorted_objects = {}
               local best_index, best_score_time, best_score_dist
               for index, patrollable_object in pairs(new_list) do
                  local score_time, score_dist = self:_calculate_patrol_banner_score(location, patrollable_object)
                  if not best_index or score_time < best_score_time or (score_time == best_score_time and score_dist < best_score_dist) then
                     best_index, best_score_time, best_score_dist = index, score_time, score_dist
                  end
               end

               for index = best_index, #new_list do
                  table.insert(sorted_objects, new_list[index])
               end
               for index = 1, best_index - 1 do
                  table.insert(sorted_objects, new_list[index])
               end

               return sorted_objects
            end
         end
      end
   end

   local ordered_objects = self:_ace_old_get_patrollable_objects(entity, town_player_id)
   for i = #ordered_objects, 1, -1 do
      local pb_comp = ordered_objects[i]:get_banner()
      if pb_comp then
         table.remove(ordered_objects, i)
      end
   end

   if #ordered_objects < 1 and not self:_get_auto_patrol(town_player_id) then
      return self:_ace_old_get_patrollable_objects(entity, town_player_id, true)
   end

   return ordered_objects
end

-- Returns an array of patrollable objects for this entity, sorted by priority.
function TownPatrol:_ace_old_get_patrollable_objects(entity, town_player_id, auto_override)
   local location = radiant.entities.get_world_location(entity)
   local ordered_objects = {}

   if location then
      local scores = {}
      local unleased_objects = self:_get_unleased_objects(entity, town_player_id, auto_override)
      -- score each object based on the benefit/cost ratio of patrolling it
      for object_id, patrollable_object in pairs(unleased_objects) do
         local score = self:_calculate_patrol_score(location, patrollable_object)
         scores[patrollable_object] = score
         table.insert(ordered_objects, patrollable_object)
      end

      -- order the objects by descending score
      table.sort(ordered_objects,
         function (a, b)
            return scores[a] > scores[b]
         end)
   end

   -- return the whole ordered object array
   return ordered_objects
end

function TownPatrol:_get_unleased_objects(entity, town_player_id, auto_override)
   local player_id = town_player_id or radiant.entities.get_player_id(entity)
   local player_patrollable_objects = (auto_override and self:_get_auto_patrollable_objects(player_id)) or self:_get_patrollable_objects(player_id)
   local unleased_objects = {}

   for object_id, patrollable_object in pairs(player_patrollable_objects) do
      if patrollable_object:can_acquire_lease(entity) then
         unleased_objects[object_id] = patrollable_object
      end
   end

   return unleased_objects
end

function TownPatrol:_calculate_patrol_banner_score(start_location, patrollable_object)
   -- primary order is based on when the point was last visited
   return patrollable_object:get_last_patrol_time(), start_location:distance_to_squared(patrollable_object:get_centroid())
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
      end
      
      -- if it's a patrol banner, add it to the patrol banner controller
      if patrollable_object:get_banner() then
         local banners = self:get_patrol_banners(player_id)
         banners:add_banner(patrollable_object)
      end

      -- we need to do this no matter what because we might be in manual patrol mode but the only manual patrol points
      -- are patrol banners for other parties, and this could be an auto patrol point that would work for them
      self:_trigger_patrol_route_available(player_id)

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
      
      -- remove from the relevant player patrol banner controller
      local banners = self:get_patrol_banners(player_id)
      banners:remove_banner(object_id)
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
