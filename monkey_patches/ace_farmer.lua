local log = radiant.log.create_logger('farmer')

local FarmerClass = radiant.mods.require('stonehearth.jobs.farmer.farmer')
local AceFarmerClass = class()

AceFarmerClass._old__create_listeners = FarmerClass._create_listeners
function AceFarmerClass:_create_listeners()
   self:_old__create_listeners()
   self._on_plant_listener = radiant.events.listen(self._sv._entity, 'stonehearth:plant_crop', self, self._on_plant)
   self._on_fertilize_listener = radiant.events.listen(self._sv._entity, 'stonehearth_ace:fertilize_crop', self, self._on_fertilize)
end

AceFarmerClass._old__remove_listeners = FarmerClass._remove_listeners
function AceFarmerClass:_remove_listeners()
   self:_old__remove_listeners()
   if self._on_plant_listener then
      self._on_plant_listener:destroy()
      self._on_plant_listener = nil
   end
   if self._on_fertilize_listener then
      self._on_fertilize_listener:destroy()
      self._on_fertilize_listener = nil
   end
end

function AceFarmerClass:_on_plant()
   -- exp gained from planting will not level up the farmer
   local xp_to_add = math.min(self._job_component:get_xp_to_next_lv() - self._job_component:get_current_exp() - 1, self._xp_rewards["base_exp_per_plant"])
   if xp_to_add > 0 then
      --log:debug('adding planting exp %s: %s until next level', xp_to_add, self._job_component:get_xp_to_next_lv() - self._job_component:get_current_exp())
      self._job_component:add_exp(xp_to_add, false, {only_through_level = 2})
   end
end

function AceFarmerClass:_on_fertilize()
   local xp_to_add = self._xp_rewards["base_exp_per_fertilize"]
   self._job_component:add_exp(xp_to_add)
end

return AceFarmerClass
