local Depart = class()

Depart.name = 'depart'
Depart.does = 'stonehearth_ace:merchant:depart'
Depart.args = {}
Depart.priority = 1

function Depart:start_thinking(ai, entity, args)
   if entity:get_component('stonehearth_ace:merchant'):should_depart() then
      ai:set_think_output()
   else
      self._depart_time_listener = radiant.events.listen(stonehearth_ace.mercantile, 'stonehearth_ace:merchants:depart_time', function()
            ai:set_think_output()
         end)
   end
end

function Depart:stop_thinking(ai, entity, args)
   self:destroy()
end

function Depart:destroy()
   if self._depart_time_listener then
      self._depart_time_listener:destroy()
      self._depart_time_listener = nil
   end
end

function Depart:run(ai, entity, args)
   entity:get_component('stonehearth_ace:merchant'):take_down_from_stall()
   stonehearth_ace.mercantile:remove_merchant(entity)
   ai:execute('stonehearth:depart_visible_area', { give_up_after = '1h' })
end

return Depart
