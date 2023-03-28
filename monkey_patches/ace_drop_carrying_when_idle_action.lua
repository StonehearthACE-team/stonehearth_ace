--local DropCarryingWhenIdle = require 'stonehearth.ai.actions.drop_carrying_when_idle_action'
local AceDropCarryingWhenIdle = radiant.class()

local WAIT_BEFORE_DROPPING = '2m'

--AceDropCarryingWhenIdle._ace_old_start_thinking = DropCarryingWhenIdle.start_thinking
function AceDropCarryingWhenIdle:start_thinking(ai, entity, args)
   if args.hold_position then
      return
   end

   -- if ai.CURRENT.carrying then
   --    -- if we're carrying any destroy_on_uncarry item, don't idly drop it!
   --    local carried_item_data = radiant.entities.get_entity_data(ai.CURRENT.carrying, 'stonehearth:item')
   --    if carried_item_data and carried_item_data.destroy_on_uncarry then
   --       return
   --    end
   -- end

   local backpack = entity:get_component('stonehearth:storage')
   local items_in_backpack = backpack and not backpack:is_empty()

   if ai.CURRENT.carrying or items_in_backpack then
      self._wait_before_dropping_timer = stonehearth.calendar:set_timer('wait before idly dropping items', WAIT_BEFORE_DROPPING, function()
            ai:set_think_output()
         end)
   end
end

function AceDropCarryingWhenIdle:stop_thinking(ai, entity, args)
   if self._wait_before_dropping_timer then
      self._wait_before_dropping_timer:destroy()
      self._wait_before_dropping_timer = nil
   end
end

return AceDropCarryingWhenIdle
