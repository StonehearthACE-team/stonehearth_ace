local FishTrapComponent = class()

function FishTrapComponent:initialize()
   self._sv._applied_buff = nil    -- keep track of whether we've applied a buff, just in case
   self._sv._water_component = nil  -- the water the trap is in
	
	local limit_data = radiant.entities.get_entity_data(self._entity, 'stonehearth:item_placement_limit')
   self._trap_type = limit_data and limit_data.tag
	self.__saved_variables:mark_changed()
end

function FishTrapComponent:activate()
   local json = radiant.entities.get_json(self)
   self._buff_name = json.buff
   
	if self._trap_type then
      self._parent_listener = self._entity:add_component('mob'):trace_parent('fish trap placed or removed')
         :on_changed(function(parent)
            self:_on_parent_changed(parent)
         end)
         :push_object_state()
   end
end

function FishTrapComponent:destroy()
   self:_destroy_listeners()
	
	if self._trap_type then
      self:_register_with_town(false)
   end
end

function FishTrapComponent:_destroy_listeners()
   if self._parent_listener then
      self._parent_listener:destroy()
      self._parent_listener = nil
   end
end

function FishTrapComponent:_register_with_town(register)
   local player_id = radiant.entities.get_player_id(self._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      if register then
         town:register_limited_placement_item(self._entity, self._trap_type)
      else
         town:unregister_limited_placement_item(self._entity, self._trap_type)
      end
   end
end

function FishTrapComponent:_on_parent_changed(parent)
   if not parent then
      local entity_forms_component = self._entity:get_component('stonehearth:entity_forms')
      if entity_forms_component and not entity_forms_component:is_being_placed() then
         -- Unregister this object if it was undeployed
         self:_register_with_town(false)
      end
   else
      -- Register this object if it is placed
      self:_register_with_town(true)
   end

   -- if there's a parent (we're placed) and we haven't applied a buff, or vice versa, add/remove the buff
   if (parent == nil) ~= (self._sv._applied_buff == nil) then

   end
end

function FishTrapComponent:set_water_component(water)
   self._sv._water_component = water
   self.__saved_variables:mark_changed()
end

return FishTrapComponent