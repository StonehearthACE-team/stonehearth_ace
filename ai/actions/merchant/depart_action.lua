local Depart = class()

Depart.name = 'depart'
Depart.does = 'stonehearth_ace:merchant:depart'
Depart.args = {}
Depart.priority = 1

function Depart:start_thinking(ai, entity, args)
   if entity:get_component('stonehearth_ace:merchant'):should_depart() then
      ai:set_think_output()
   end
end

function Depart:run(ai, entity, args)
   stonehearth_ace.mercantile:remove_merchant(entity)
   ai:execute('stonehearth:depart_visible_area', { give_up_after = '1h' })
end

return Depart
