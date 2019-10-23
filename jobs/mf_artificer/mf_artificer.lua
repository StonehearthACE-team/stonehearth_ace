local CraftingJob = require 'stonehearth.jobs.crafting_job'

local HELPER_RECIPES = {
   ['stonehearth:jobs:blacksmith'] = {
      'tools:automaton_drill',
	  'refined:automaton_parts',
   },
   ['stonehearth:jobs:weaver'] = {
      'crafting_materials:automaton_backpack',
   },
}

local ArtificerClass = class()
radiant.mixin(ArtificerClass, CraftingJob)

function ArtificerClass:initialize()
   CraftingJob.__user_initialize(self)
   self._sv.max_num_automatons = {}
   self._sv.max_num_siege_weapons = {}
end

function ArtificerClass:activate()
   CraftingJob.activate(self)

   if self._sv.is_current_class then
      self:_register_with_town()
   end

   self.__saved_variables:mark_changed()
end

function ArtificerClass:restore()
   if self._sv.is_current_class then
      self:_register_with_town()
   end
end

function ArtificerClass:promote(json_path, options)
   CraftingJob.promote(self, json_path, options)
   self._sv.max_num_automatons = { automaton = 0 }
   self._sv.max_num_siege_weapons = self._job_json.initial_num_siege_weapons or { turret = 0, trap = 0 }
   if next(self._sv.max_num_siege_weapons) then
      self:_register_with_town()
   end
   self.__saved_variables:mark_changed()
end

function ArtificerClass:demote()
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:remove_placement_slot_entity(self._sv._entity)
   end

   CraftingJob.demote(self)
end

function ArtificerClass:increase_max_devices(perk_json)
   self._sv.max_num_automatons = { automaton = perk_json.max_num_automatons }
   self._sv.max_num_siege_weapons = perk_json.max_num_siege_weapons
   self:_register_with_town()
   self.__saved_variables:mark_changed()
end

function ArtificerClass:_create_listeners()
   CraftingJob._create_listeners(self)
   self._on_repair_entity_listener = radiant.events.listen(self._sv._entity, 'stonehearth:repaired_entity', self, self._on_repaired_entity)
end

function ArtificerClass:_remove_listeners()
   CraftingJob._remove_listeners(self)
   if self._on_repair_entity_listener then
      self._on_repair_entity_listener:destroy()
      self._on_repair_entity_listener = nil
   end
end

function ArtificerClass:_on_repaired_entity(args)
   local key = args.action or 'repair_entity'
   local exp = self._xp_rewards[key]
   if exp then
      self._job_component:add_exp(exp)
   end
end

function ArtificerClass:_register_with_town()
   local player_id = radiant.entities.get_player_id(self._sv._entity)

   -- Enforce automaton and trap/turret limit.
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:add_placement_slot_entity(self._sv._entity, self._sv.max_num_automatons)
	  town:add_placement_slot_entity(self._sv._entity, self._sv.max_num_siege_weapons)
   end
   
   -- Unlock recipes for other classes used by the artificer.
   for job, recipe_keys in pairs(HELPER_RECIPES) do
      local job_info = stonehearth.job:get_job_info(player_id, job)
      for _, recipe_key in ipairs(recipe_keys) do
         job_info:manually_unlock_recipe(recipe_key)
      end
   end
end

return ArtificerClass
