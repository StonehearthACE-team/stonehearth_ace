local PlayerService = require 'stonehearth.services.server.player.player_service'
local AcePlayerService = class()

local log = radiant.log.create_logger('player_service')

--If the kingdom is not already specified for this player, add it now
AcePlayerService._ace_old_add_kingdom = PlayerService.add_kingdom
function AcePlayerService:add_kingdom(player_id, kingdom)
   self:_ace_old_add_kingdom(player_id, kingdom)

   log:debug('triggering "radiant:player_kingdom_assigned" for player_id "%s"', player_id)
   radiant.events.trigger(radiant, 'radiant:player_kingdom_assigned', {player_id = player_id})
end

--For the client, given a player, get their kingdom's job index
function AcePlayerService:get_job_index(session, response, entity)
   local job = entity and entity:get_component('stonehearth:job')
   local population = job and job:get_population_override()
   return {job_index = self:get_job_index_for_player(session.player_id, population)}
end

function AcePlayerService:get_job_index_for_player(player_id, population_override)
   local pop = stonehearth.population:get_population(player_id)
   return pop:get_job_index(population_override)
end

function AcePlayerService:get_jobs(player_id, population_override)
   local job_index = self:get_job_index_for_player(player_id, population_override)

   if not self._jobs[job_index] then
      self._jobs[job_index] = radiant.deep_copy(radiant.resources.load_json(job_index).jobs)
   end

   return self._jobs[job_index]
end

function AcePlayerService:get_default_base_job(player_id, population_override)
   if not self._default_base_job then
      local job_index = self:get_job_index_for_player(player_id, population_override)
      local base_job = job_index and radiant.resources.load_json(job_index).base_job or stonehearth.constants.job.DEFAULT_BASE_JOB
      self._default_base_job = base_job
   end

   return self._default_base_job
end

AcePlayerService._ace_old_add_player = PlayerService.add_player
function AcePlayerService:add_player(player_id, kingdom, options)
   self:_ace_old_add_player(player_id, kingdom, options)
   
   if not (options and options.is_npc) then
      stonehearth_ace.mercantile:add_player_controller(player_id, true)
   end
end

-- Clean up data for this player
AcePlayerService._ace_old_remove_player = PlayerService.remove_player
function AcePlayerService:remove_player(player_id)
   -- TODO: mercantile service once it's made; figure out what else might need to be handled
   stonehearth_ace.mercantile:remove_player(player_id)

   self:_ace_old_remove_player(player_id)
end

return AcePlayerService
