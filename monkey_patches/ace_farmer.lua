local log = radiant.log.create_logger('farmer')

local FarmerClass = radiant.mods.require('stonehearth.jobs.farmer.farmer')
local AceFarmerClass = class()

AceFarmerClass._ace_old__create_listeners = FarmerClass._create_listeners
function AceFarmerClass:_create_listeners()
   self:_ace_old__create_listeners()
   self._on_plant_listener = radiant.events.listen(self._sv._entity, 'stonehearth:plant_crop', self, self._on_plant)
   self._on_fertilize_listener = radiant.events.listen(self._sv._entity, 'stonehearth_ace:fertilize_crop', self, self._on_fertilize)
end

AceFarmerClass._ace_old__remove_listeners = FarmerClass._remove_listeners
function AceFarmerClass:_remove_listeners()
   self:_ace_old__remove_listeners()
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
   local xp_to_add = self._xp_rewards["base_exp_per_plant"]
   self._job_component:add_exp(xp_to_add, false, {only_through_level = 2})
end

function AceFarmerClass:_on_fertilize()
   local xp_to_add = self._xp_rewards["base_exp_per_fertilize"]
   self._job_component:add_exp(xp_to_add)
end

return AceFarmerClass
