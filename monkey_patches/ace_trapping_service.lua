local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local rng = _radiant.math.get_default_rng()

local TrappingService = require 'stonehearth.services.server.trapping.trapping_service'
AceTrappingService = class()

-- AceTrappingService._ace_old_destroy = TrappingService.__user_destroy
-- function AceTrappingService:destroy()
--    self:_destroy_all_listeners()
--    self:_ace_old_destroy()
-- end

-- function AceTrappingService:_destroy_all_listeners()
--    if self._fish_traps then
--       for _, trap_data in pairs(self._fish_traps) do
--          self:_destroy_predestroy_listener(trap_data)
--       end
--    end
-- end

-- function AceTrappingService:_destroy_predestroy_listener(trap_data)
--    if trap_data.water_predestroy_listener then
--       trap_data.water_predestroy_listener:destroy()
--       trap_data.water_predestroy_listener = nil
--    end
-- end

-- register fish traps and index them by the water entity they fish from
-- making it easy for a trap to check what other traps it might be contesting
function AceTrappingService:register_fish_trap(trap, water_entity)
   if not self._fish_traps then
      self._fish_traps = {}
   end

   local water_id = water_entity:get_id()
   local trap_data = self._fish_traps[water_id]
   if not trap_data then
      trap_data = {
         traps = {},
         water_entity = water_entity,
         -- water_predestroy_listener = radiant.events.listen(water_entity, 'radiant:entity:pre_destroy', function()
         --       self:_remove_water_entity(water_id)
         --    end)
      }

      self._fish_traps[water_id] = trap_data
   end

   local trap_id = trap:get_id()
   trap_data.traps[trap_id] = trap
   self:_queue_inform_traps_of_potential_conflict(water_id, trap_id)
end

function AceTrappingService:unregister_fish_trap(trap_id, water_id)
   local trap_data = self._fish_traps and self._fish_traps[water_id]
   if trap_data then
      trap_data.traps[trap_id] = nil
      if next(trap_data.traps) then
         self:_queue_inform_traps_of_potential_conflict(water_id)
      else
         self:_remove_water_entity(water_id)
      end
   end
end

function AceTrappingService:_remove_water_entity(water_id)
   local trap_data = self._fish_traps and self._fish_traps[water_id]
   if trap_data then
      -- self:_destroy_predestroy_listener(trap_data)
      -- for _, trap in pairs(trap_data.traps) do
      --    local trap_component = trap:get_component('stonehearth_ace:fish_trap')
      --    if trap_component then
      --       trap_component:recheck_water_entity()
      --    end
      -- end
      self._fish_traps[water_id] = nil
   end
end

function AceTrappingService:_queue_inform_traps_of_potential_conflict(water_id, except_trap_id)
   if not self._queued_inform then
      self._queued_inform = {}
   end

   local queued = self._queued_inform[water_id]
   if queued then
      if queued.except_trap_id ~= except_trap_id then
         queued.except_trap_id = nil
      end
   else
      self._queued_inform[water_id] = {except_trap_id = except_trap_id}
   end

   if not self._on_next_game_loop then
      self._on_next_game_loop = radiant.on_game_loop_once('inform fish traps of potential conflicts', function()
            local queued = self._queued_inform
            self._queued_inform = {}
            self._on_next_game_loop = nil

            for water_id, detail in pairs(queued) do
               local trap_data = self._fish_traps[water_id]
               if trap_data then
                  self:_inform_traps_of_potential_conflict(trap_data.traps, detail.except_trap_id)
               end
            end
         end)
   end
end

function AceTrappingService:_inform_traps_of_potential_conflict(traps, except_id)
   for trap_id, trap in pairs(traps) do
      if trap_id ~= except_id then
         local trap_component = trap:get_component('stonehearth_ace:fish_trap')
         if trap_component then
            trap_component:recheck_effective_water_volume()
         end
      end
   end
end

function AceTrappingService:get_fish_traps_in_water(water_id)
   local trap_data = self._fish_traps and self._fish_traps[water_id]
   if trap_data then
      return radiant.shallow_copy(trap_data.traps)
   end
end

function AceTrappingService:get_num_fish_traps_in_water(water_id)
   local trap_data = self._fish_traps and self._fish_traps[water_id]
   return trap_data and radiant.size(trap_data.traps) or 0
end

return AceTrappingService
