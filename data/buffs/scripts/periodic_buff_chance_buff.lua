-- Adds a timer with a random chance to apply a certain buff
-- every time the timer ticks
local rng = _radiant.math.get_default_rng()

local PeriodicBuffChance = class()

function PeriodicBuffChance:on_buff_added(entity, buff)
   local json = buff:get_json()
   self._tuning = json.script_info
   if not self._tuning or not self._tuning.periodic_chance_buff.buff_uri then
      return
   end
   local tick_duration = self._tuning.tick or "1h"
   self._entity = entity
   self._buff = buff
   -- check if this buff's listener already exists (meaning it's a buff renewal) and tick it
   -- to make sure that you get ticks for buffs that are re-applied faster than their timers
   if self._tick_listener then
      self:_on_tick()
   else
      self._tick_listener = stonehearth.calendar:set_interval("Periodic Buff Chance "..buff:get_uri().." tick", tick_duration, 
         function()
            self:_on_tick()
         end)
   end
end

function PeriodicBuffChance:_on_tick()
	-- check if the entity has an immunity buff that prevents this periodic buff to have a chance to be added
	if self._tuning.periodic_chance_buff.immunity_uri and radiant.entities.has_buff(self._entity, self._tuning.periodic_chance_buff.immunity_uri) then
		return
	end

   local periodic_chance_buff = self._tuning.periodic_chance_buff.buff_uri
   local stacks = self._buff:get_stacks() or 1
   local chance = self._tuning.chance and math.min(1, self._tuning.chance * stacks) or 0.5
   if rng:get_real(0, 1) < chance then
      radiant.entities.add_buff(self._entity, periodic_chance_buff)
   end  
end

function PeriodicBuffChance:on_buff_removed(entity, buff)
   if self._tick_listener then
      self._tick_listener:destroy()
      self._tick_listener = nil
   end
end

return PeriodicBuffChance
