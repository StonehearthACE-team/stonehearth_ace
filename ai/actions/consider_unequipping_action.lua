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
      local items = {}
      -- go through each item and check if it should be unequipped
      for slot, item in pairs(equipment:get_all_items()) do
         local ep_comp = item:get_component('stonehearth:equipment_piece')
         if ep_comp:get_can_unequip() then
            local value = ep_comp:get_value(self._entity:get_component('stonehearth:job'))
            if value and value < 0 then
               table.insert(items, item)
            end
         end
      end

      if #items > 0 then
         self._items = items
         self._ai:set_think_output()
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

function ConsiderUnequipping:run(ai, entity, args)
   local equipment = self._entity:get_component('stonehearth:equipment')
   if equipment then
      for _, item in ipairs(self._items) do
         local unequipped = equipment:unequip_item(item, true)  -- true to try replacing with a default item

         -- just drop it, who cares?! no action needed
         -- maybe in the future do an animation for it or something
         if unequipped then
            local should_drop = unequipped:get_component('stonehearth:equipment_piece')
                                       :get_should_drop()
            if should_drop then
               local location = radiant.entities.get_world_grid_location(entity)
               local drop_location = radiant.terrain.find_placement_point(location, 0, 2)
               radiant.terrain.place_entity(unequipped, drop_location)
            else
               radiant.entities.destroy_entity(unequipped)
            end
         end
      end
   end
end

return ConsiderUnequipping
