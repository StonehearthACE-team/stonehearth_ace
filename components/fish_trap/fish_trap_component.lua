local FishTrapComponent = class()

function FishTrapComponent:initialize()
   self._sv._applied_buff = nil    -- keep track of whether we've applied a buff, just in case
   self._sv._water_component = nil  -- the water the trap is in
end

function FishTrapComponent:activate()
   local json = radiant.entities.get_json(self)
   self._buff_name = json.buff
   
   self:_create_listeners()
end

function FishTrapComponent:destroy()
   self:_destroy_listeners()
end

function FishTrapComponent:_create_listeners()
   self._parent_listener = self._entity:add_component('mob'):trace_parent('fish trap placed or removed')
      :on_changed(function(parent)
         self:_on_parent_changed(parent)
      end)
end

function FishTrapComponent:_destroy_listeners()
   if self._parent_listener then
      self._parent_listener:destroy()
      self._parent_listener = nil
   end
end

function FishTrapComponent:_on_parent_changed(parent)
   -- if there's a parent (we're placed) and we haven't applied a buff, or vice versa, add/remove the buff
   if (parent == nil) ~= (self._sv._applied_buff == nil) then

   end
end

function FishTrapComponent:set_water_component(water)
   self._sv._water_component = water
   self.__saved_variables:mark_changed()
end

return FishTrapComponent