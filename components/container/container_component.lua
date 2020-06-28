local log = radiant.log.create_logger('container')

local ContainerComponent = class()

-- "contains" a specified number of something
-- DOES NOT contain actual entities; it's more of a ledger

function ContainerComponent:create()
	local json = radiant.entities.get_json(self)
	self._sv.type = json.type
	self._sv.capacity = json.capacity
	self._sv.volume = math.min(self._sv.capacity, json.starting_volume or 0)
	self.__saved_variables:mark_changed()
end

function ContainerComponent:get_type()
	return self._sv.type
end

function ContainerComponent:get_total_capacity()
	return self._sv.capacity
end

function ContainerComponent:get_available_capacity(type)
   if type and type ~= self._sv.type then
      return 0
   end

	return self._sv.capacity - self._sv.volume
end

function ContainerComponent:get_volume()
   return self._sv.volume
end

function ContainerComponent:is_empty()
   return self._sv.volume <= 0
end

function ContainerComponent:is_full()
   return self._sv.volume >= self._sv.capacity
end

function ContainerComponent:clear(type)
   if not type or type == self._sv.type then
      self._sv.volume = 0
      self.__saved_variables:mark_changed()
   end
end

-- returns the volume we failed to add
function ContainerComponent:add_volume(type, volume)
	if type ~= self._sv.type then
		-- cannot add this type
		return volume
	end
	
	if volume <= 0 then
		-- we don't add negative volume; use remove_volume for that
		return volume
	end

	if self._sv.volume >= self._sv.capacity then
		-- we're already at capacity; we can't add any of this
		return volume
	end

	local amount_to_add = math.min(self:get_available_capacity(), volume)
	self._sv.volume = self._sv.volume + amount_to_add
	self.__saved_variables:mark_changed()
	return volume - amount_to_add
end

-- returns the volume we failed to remove
function ContainerComponent:remove_volume(type, volume)
	if type ~= self._sv.type then
		-- cannot add this type
		return volume
	end
	
	if volume <= 0 then
		-- we don't remove negative volume; use add_volume for that
		return volume
	end

	if self._sv.volume <= 0 then
		-- we're already empty; we can't remove any of this
		return volume
	end

	local amount_to_remove = math.min(self._sv.volume, volume)
	self._sv.volume = self._sv.volume - amount_to_remove
	self.__saved_variables:mark_changed()
	return volume - amount_to_remove
end

return ContainerComponent
