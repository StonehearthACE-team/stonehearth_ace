local Town = require 'stonehearth.services.server.town.town'
local AceTown = class()

AceTown._ace_old__requirements_met = Town._requirements_met
function AceTown:_requirements_met(person, job_uri)
   local job_component = person:get_component('stonehearth:job')
   local player_id = radiant.entities.get_player_id(person)
   local base_job = stonehearth.player:get_default_base_job(player_id)

   -- if person already has a controller for that job
   if job_component:get_controller(job_uri) or job_uri == base_job then
      return true
   end

   -- convert to appropriate kingdom
   local player_id = radiant.entities.get_player_id(person)
   local job_index = stonehearth.player:get_jobs(player_id)
   local mod_job_uri = job_index[job_uri].description

   -- get desired job information
   local job_data = radiant.resources.load_json(mod_job_uri)

   -- if desired job's parent is worker
   if job_data.parent_job == base_job then
      return true
   end

   -- if there are multiple parents, check for each of them
   -- If we can't have the parent job, ignore that requirement.
   local parent_jobs = job_data.parent_jobs or {{job = job_data.parent_job, level_requirement = job_data.parent_level_requirement}}
   local allowable_jobs = job_component:get_allowed_jobs()
   if allowable_jobs then
      for id, parent_job in pairs(parent_jobs) do
         if not allowable_jobs[parent_job.job] then
            parent_jobs[parent_job.job] = nil
         end
      end
   end

   local one_of = nil
   for id, parent_job in pairs(parent_jobs) do
      local parent_controller = job_component:get_controller(parent_job.job)
      local required_level = parent_job.level_requirement or 0

      if parent_job.one_of then
         if one_of == nil then
            one_of = false
         end
         if parent_controller and parent_controller:get_job_level() >= required_level then
            one_of = true
         end
      else
         if parent_controller then
            -- if the parent doesn't meet the level requirement, it fails
            if parent_controller:get_job_level() < required_level then
               return false
            end
         else
            -- if there is no controller for the parent, it fails
            return false
         end
      end
   end

   -- if there were no allowable parent job requirements, or they were all met, it succeeds
   return one_of ~= false
end

function AceTown:register_entity_type(type, entity)
   if not self._sv._registered_entity_types then
      self._sv._registered_entity_types = {}
   end
   if not self._sv._registered_entity_types[type] then
      self._sv._registered_entity_types[type] = {}
   end
   self._sv._registered_entity_types[type][entity:get_id()] = true
   self.__saved_variables:mark_changed()
end

function AceTown:unregister_entity_type(type, entity)
   if self._sv._registered_entity_types and self._sv._registered_entity_types[type] then
      self._sv._registered_entity_types[type][entity:get_id()] = nil
      self.__saved_variables:mark_changed()
   end
end

function AceTown:unregister_entity_types(entity)
   if self._sv._registered_entity_types then
      for _, type_tbl in pairs(self._sv._registered_entity_types) do
         type_tbl[entity:get_id()] = nil
      end
   end
   self.__saved_variables:mark_changed()
end

function AceTown:is_entity_type_registered(type)
   local registered = self._sv._registered_entity_types and self._sv._registered_entity_types[type]
   return registered and next(registered) ~= nil
end

return AceTown
