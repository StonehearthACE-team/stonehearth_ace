local CraftingJob = require 'stonehearth.jobs.crafting_job'

local GrowerClass = class()
radiant.mixin(GrowerClass, CraftingJob)

function GrowerClass:initialize()
   CraftingJob.initialize(self)
   self._sv.max_num_attended_hearthlings = 2
end

function GrowerClass:create(entity)
   CraftingJob.create(self, entity)
end

function GrowerClass:restore()
   if self._sv.is_current_class then
      self:_register_with_town()
   end
end

function GrowerClass:promote(json_path, options)
   CraftingJob.promote(self, json_path, options)
   self._sv.max_num_attended_hearthlings = self._job_json.initial_num_attended_hearthlings or 2
   if self._sv.max_num_attended_hearthlings > 0 then
      self:_register_with_town()
   end
   self.__saved_variables:mark_changed()
end

function GrowerClass:increase_attended_hearthlings(args)
   self._sv.max_num_attended_hearthlings = args.max_num_attended_hearthlings
   self:_register_with_town() -- re-register with the town because number of max attended hearthlings is increased
   self.__saved_variables:mark_changed()
end

-- Registers the medic with the town
function GrowerClass:_register_with_town()
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:add_medic(self._sv._entity, self._sv.max_num_attended_hearthlings)
   end
end

-- Called when destroying this entity, we should alo remove ourselves
function GrowerClass:_unregister_with_town()
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:remove_medic(self._sv._entity)
   end
end

function GrowerClass:_create_listeners()
   CraftingJob._create_listeners(self)
   self._on_harvest_listener = radiant.events.listen(self._sv._entity, 'stonehearth:harvest_crop', self, self._on_harvest)
   self._on_heal_entity_listener = radiant.events.listen(self._sv._entity, 'stonehearth:healer:healed_entity', self, self._on_healed_entity)
end

function GrowerClass:_remove_listeners()
   CraftingJob._remove_listeners(self)
   if self._on_harvest_listener then
      self._on_harvest_listener:destroy()
      self._on_harvest_listener = nil
   end
   if self._on_heal_entity_listener then
      self._on_heal_entity_listener:destroy()
      self._on_heal_entity_listener = nil
   end
end

function GrowerClass:_on_healed_entity(args)
   local exp = self._xp_rewards['heal_entity']
   if exp then
      self._job_component:add_exp(exp)
   end
end

function GrowerClass:_on_harvest(args)
   local crop = args.crop_uri
   local xp_to_add = self._xp_rewards["base_exp_per_harvest"]
   if self._xp_rewards[crop] then
      xp_to_add = self._xp_rewards[crop] 
   end
   self._job_component:add_exp(xp_to_add)
end

-- Call when it's time to demote
function GrowerClass:demote()
   self:_unregister_with_town()

   CraftingJob.demote(self)
end

-- Called when destroying this entity
-- Note we could get destroyed without being demoted
-- So remove ourselves from town just in case
function GrowerClass:destroy()
   if self._sv.is_current_class then
      self:_unregister_with_town()
   end

   CraftingJob.destroy(self)
end
return GrowerClass
