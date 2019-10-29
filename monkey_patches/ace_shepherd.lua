local log = radiant.log.create_logger('shepherd')
local rng = _radiant.math.get_default_rng()

local ShepherdClass = radiant.mods.require('stonehearth.jobs.shepherd.shepherd')
local BaseJob = require 'stonehearth.jobs.base_job'
local AceShepherdClass = class()

function AceShepherdClass:initialize()
   BaseJob.__user_initialize(self)
   self._sv.last_found_critter_time = nil
   self._sv.trailed_animals = nil
   self._sv.num_trailed_animals = 0
end

function AceShepherdClass:destroy()
   if self._sv.is_current_class then
      self:_abandon_following_animals()
   end

   BaseJob.__user_destroy(self)
end

AceShepherdClass._ace_old_can_find_animal_in_world = ShepherdClass.can_find_animal_in_world
function AceShepherdClass:can_find_animal_in_world()
   if radiant.entities.has_buff(self._sv._entity, 'stonehearth_ace:buffs:shepherd:stenched_minor') then
      return false
   end

   return self:_ace_old_can_find_animal_in_world()
end

function AceShepherdClass:_on_resource_gathered(args)
   if args.harvested_target then
      local equipment_component = args.harvested_target:get_component('stonehearth:equipment')
      if equipment_component and equipment_component:has_item_type('stonehearth:pasture_equipment:tag') then
         self._job_component:add_exp(self._xp_rewards['harvest_animal'])
         if self:has_perk('improved_buffs') then
            radiant.entities.add_buff(self._sv._entity, 'stonehearth_ace:buffs:shepherd:stenched_minor');
         else
            radiant.entities.add_buff(self._sv._entity, 'stonehearth:buffs:shepherd:stenched');
         end
      end
   end
end

function AceShepherdClass:_on_interacted_with_animal(animal)
   local attributes = self._sv._entity:get_component('stonehearth:attributes')
   if attributes then
      local compassion = attributes:get_attribute('compassion') or 0
      local buff_chance = compassion * stonehearth.constants.attribute_effects.COMPASSION_SHEPHERD_BUFF_CHANCE_MULTIPLIER
      local roll = rng:get_int(1, 100)  
      if roll <= buff_chance then
         if self:has_perk('improved_buffs') then
            radiant.entities.add_buff(animal, 'stonehearth_ace:buffs:shepherd:compassionate_shepherd_major');
         else
            radiant.entities.add_buff(animal, 'stonehearth:buffs:shepherd:compassionate_shepherd');
         end        
      end
   end
end

return AceShepherdClass
