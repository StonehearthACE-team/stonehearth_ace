local DoorComponent = radiant.mods.require('stonehearth.components.door.door_component')
local AceDoorComponent = class()

local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local log = radiant.log.create_logger('door')

local DOOR_FILTERS = {}

local ALWAYS_FALSE_FRC = nil

local get_always_false_filter = function()
   if not ALWAYS_FALSE_FRC then
      local filter_fn = function(entity)
         return false
      end

      ALWAYS_FALSE_FRC = stonehearth.ai:create_filter_result_cache(filter_fn, ' always false door movement_guard_shape frc')
   end
   return ALWAYS_FALSE_FRC
end

local get_door_filter = function(door_entity)
   local player_id = radiant.entities.get_player_id(door_entity)
   local filter = DOOR_FILTERS[player_id]
   if not filter then
      local filter_fn = function(entity)
         local entity_player_id = radiant.entities.get_player_id(entity)
         local is_not_hostile = stonehearth.player:are_player_ids_not_hostile(player_id, entity_player_id)

         if not is_not_hostile then
            return false
         end

         -- also disallow pasture animals from opening doors
         -- (still allow critters to do it so they don't get stuck away from food, etc.)
         local equipment = entity:is_valid() and entity:get_component('stonehearth:equipment')
         local tag = equipment and equipment:has_item_type('stonehearth:pasture_equipment:tag')
         local shepherded = tag and tag:get_component('stonehearth:shepherded_animal')

         return not shepherded or shepherded:get_following()
      end

      local frc = stonehearth.ai:create_filter_result_cache(filter_fn, player_id .. ' door movement_guard_shape frc')
      local amenity_changed_listener = radiant.events.listen(radiant, 'stonehearth:amenity:sync_changed', function(e)
            local faction_a = e.faction_a
            local faction_b = e.faction_b
            if player_id == faction_a or player_id == faction_b then
               if frc and frc.cache then
                  frc.cache:clear()
               end
            end
         end)
      filter = {
         frc = frc,
         listener = amenity_changed_listener
      }
      DOOR_FILTERS[player_id] = filter
   end
   return filter
end

AceDoorComponent._ace_old_activate = DoorComponent.activate
function AceDoorComponent:activate(entity, json)
   self._shepherded_animal_listeners = {}
   self:_ace_old_activate(entity, json)
end

AceDoorComponent._ace_old_destroy = DoorComponent.destroy
function AceDoorComponent:destroy()
   self:_destroy_shepherded_animal_listeners()
   self:_ace_old_destroy()
end

function AceDoorComponent:_destroy_shepherded_animal_listeners()
   for id, listener in pairs(self._shepherded_animal_listeners) do
      listener:destroy()
      self._shepherded_animal_listeners[id] = nil
   end
end

function AceDoorComponent:_get_filter_cache()
   local player_id = radiant.entities.get_player_id(self._entity)
   if self:is_lockable() and self:is_locked() then
      return get_always_false_filter().cache
   else
      return get_door_filter(self._entity).frc.cache
   end
end

-- we're not actually using this, but let's keep it around just in case
AceDoorComponent._ace_old_add_collision_shape = DoorComponent._add_collision_shape
AceDoorComponent._ace_old_toggle_lock = DoorComponent.toggle_lock

function AceDoorComponent:_add_collision_shape()
   local portal = self._entity:get_component('stonehearth:portal')
   if portal then
      local mob = self._entity:add_component('mob')
      local mgs = self._entity:add_component('movement_guard_shape')

      local region2 = portal:get_portal_region()
	   local is_horizontal = portal:is_horizontal()
      local region3 = mgs:get_region()
      if not region3 then
         region3 = radiant.alloc_region3()
         mgs:set_region(region3)
      end
      region3:modify(function(cursor)
            cursor:clear()
            for rect in region2:each_cube() do
				if is_horizontal then
					cursor:add_unique_cube(Cube3(Point3(rect.min.x, 0, rect.min.y),
												 Point3(rect.max.x, 1, rect.max.y)))
				else
					cursor:add_unique_cube(Cube3(Point3(rect.min.x, rect.min.y, 0),
												 Point3(rect.max.x, rect.max.y, 1)))
				end
            end
         end)
   end
end

function AceDoorComponent:toggle_lock()
	self:_ace_old_toggle_lock()

	-- now adjust its collision type
	local mod = self._entity:add_component('stonehearth_ace:entity_modification')
	if self._sv.locked then
		mod:set_region_collision_type('solid')
	else
		mod:reset_region_collision_type()
	end
end

--AceDoorComponent._ace_old__on_removed_to_sensor = DoorComponent._on_removed_to_sensor
function AceDoorComponent:_on_removed_to_sensor(id, keep_listeners)
   local was_open = next(self._tracked_entities)
   self._tracked_entities[id] = nil
   -- don't do the animation if it wasn't open in the first place
   if was_open and not next(self._tracked_entities) then
      self:_close_door()
   end

   if not keep_listeners and self._shepherded_animal_listeners[id] then
      self._shepherded_animal_listeners[id]:destroy()
      self._shepherded_animal_listeners[id] = nil
   end
end

AceDoorComponent._ace_old__valid_entity = DoorComponent._valid_entity
function AceDoorComponent:_valid_entity(entity)
   if self:_ace_old__valid_entity(entity) then
      -- if it's otherwise valid, make sure that it's not a pasture animal (that's not currently following a shepherd)
      --log:debug('valid entity %s', entity)
      local equipment = entity:get_component('stonehearth:equipment')
      local tag = equipment and equipment:has_item_type('stonehearth:pasture_equipment:tag')
      local shepherded = tag and tag:get_component('stonehearth:shepherded_animal')

      if not shepherded then
         --log:debug('not shepherded')
         return true
      end

      local id = entity:get_id()
      if not self._shepherded_animal_listeners[id] then
         self._shepherded_animal_listeners[id] = radiant.events.listen(entity, 'stonehearth:shepherded_animal_follow_status_change',
            function(args)
               if args.should_follow then
                  self:_on_added_to_sensor(id, entity)
               else
                  self:_on_removed_to_sensor(id, true)
               end
            end)
      end

      --log:debug('is following: %s', shepherded:get_following())
      return shepherded:get_following()
   end
   
   return false
end

return AceDoorComponent