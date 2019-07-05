local Entity = _radiant.om.Entity

local ConsiderUnequipping = radiant.class()
ConsiderUnequipping.name = 'consider unequipping'
ConsiderUnequipping.does = 'stonehearth:work'
ConsiderUnequipping.args = {}
ConsiderUnequipping.think_output = {}
ConsiderUnequipping.priority = 0.25

function ConsiderUnequipping:start_thinking(ai, entity, args)
   self._ai = ai
   self._entity = entity
   self._ready = false
   
   self._seasons_listener = radiant.events.listen(stonehearth.seasons, 'stonehearth:seasons:changed', self, self._on_seasons_changed)
end

function ConsiderUnequipping:_on_seasons_changed()
   self:_consider_unequipping()
end

function ConsiderUnequipping:_consider_unequipping()
   local equipment = self._entity:get_component('stonehearth:equipment')
   if equipment then
      -- go through each item and check if it should be unequipped
      for slot, item in pairs(equipment:get_all_items()) do
         local ep_comp = item:get_component('stonehearth:equipment_piece')
         if ep_comp:get_can_unequip() then
            local value = ep_comp:get_value(self._entity:get_component('stonehearth:job'))
            if value and value < 0 then
               -- just drop it, who cares?! no action needed
               -- maybe in the future do an animation for it or something
               equipment:unequip_item(item, true)  -- true to try replacing with a default item
            end
         end
      end
   end
end

function ConsiderUnequipping:stop_thinking(ai, entity)
   self:destroy()
end

function ConsiderUnequipping:destroy()
   if self._seasons_listener then
      self._seasons_listener:destroy()
      self._seasons_listener = nil
   end
end

return ConsiderUnequipping
