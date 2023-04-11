local log = radiant.log.create_logger('shepherd')
local rng = _radiant.math.get_default_rng()

local ShepherdClass = radiant.mods.require('stonehearth.jobs.shepherd.shepherd')
local CraftingJob = require 'stonehearth.jobs.crafting_job'

local AceShepherdClass = class()
radiant.mixin(AceShepherdClass, CraftingJob)

-- don't think this is necessary since it isn't really adding anything? maybe it used to
-- function AceShepherdClass:destroy()
--    if self._sv.is_current_class then
--       self:_abandon_following_animals()
--    end

--    CraftingJob.__user_destroy(self)
-- end

-- the crafting job has promote, demote, _create_listeners, and _remove_listeners
-- we need to also call the shepherd job version of them and not let it get completely overridden

AceShepherdClass._ace_old_promote_craft = AceShepherdClass.promote
AceShepherdClass._ace_old_promote_shep = ShepherdClass.promote
function AceShepherdClass:promote(json_path)
   self:_ace_old_promote_craft(json_path)
   self:_ace_old_promote_shep(json_path)
end

AceShepherdClass._ace_old_demote_craft = AceShepherdClass.demote
AceShepherdClass._ace_old_demote_shep = ShepherdClass.demote
function AceShepherdClass:demote()
   self:_ace_old_demote_craft()
   self:_ace_old_demote_shep()
end

AceShepherdClass._ace_old__create_listeners_craft = AceShepherdClass._create_listeners
AceShepherdClass._ace_old__create_listeners_shep = ShepherdClass._create_listeners
function AceShepherdClass:_create_listeners()
   self:_ace_old__create_listeners_craft()
   self:_ace_old__create_listeners_shep()
end

AceShepherdClass._ace_old__remove_listeners_craft = AceShepherdClass._remove_listeners
AceShepherdClass._ace_old__remove_listeners_shep = ShepherdClass._remove_listeners
function AceShepherdClass:_remove_listeners()
   self:_ace_old__remove_listeners_craft()
   self:_ace_old__remove_listeners_shep()
end

AceShepherdClass._ace_old_can_find_animal_in_world = ShepherdClass.can_find_animal_in_world
function AceShepherdClass:can_find_animal_in_world()
   if radiant.entities.has_buff(self._sv._entity, 'stonehearth_ace:buffs:shepherd:stenched_minor') then
      return false
   end

   return self:_ace_old_can_find_animal_in_world()
end

AceShepherdClass._ace_old__on_pasture_fed = ShepherdClass._on_pasture_fed
function AceShepherdClass:_on_pasture_fed(args)
   self:_ace_old__on_pasture_fed(args)
   self._sv._entity:add_component('stonehearth_ace:statistics'):increment_stat('job_activities', 'shepherd_cares')
end

AceShepherdClass._ace_old__on_renewable_resource_gathered = ShepherdClass._on_renewable_resource_gathered
function AceShepherdClass:_on_renewable_resource_gathered(args)
   self:_ace_old__on_renewable_resource_gathered(args)
   self._sv._entity:add_component('stonehearth_ace:statistics'):increment_stat('job_activities', 'shepherd_harvests')
end

function AceShepherdClass:_on_resource_gathered(args)
   if args.harvested_target then
      local equipment_component = args.harvested_target:get_component('stonehearth:equipment')
      if equipment_component and equipment_component:has_item_type('stonehearth:pasture_equipment:tag') then
         self._job_component:add_exp(self._xp_rewards['harvest_animal'])
         self._sv._entity:add_component('stonehearth_ace:statistics'):increment_stat('job_activities', 'shepherd_slaughters')
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
         self._sv._entity:add_component('stonehearth_ace:statistics'):increment_stat('job_activities', 'shepherd_cares')
         local options = {
            source = self._sv._entity,
            source_player = self._sv._entity:get_player_id(),
         }
         if self:has_perk('improved_buffs') then
            radiant.entities.add_buff(animal, 'stonehearth_ace:buffs:shepherd:compassionate_shepherd_major', options);
         else
            radiant.entities.add_buff(animal, 'stonehearth:buffs:shepherd:compassionate_shepherd', options);
         end        
      end
   end
end

return AceShepherdClass
