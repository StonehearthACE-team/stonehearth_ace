local PlayerService = require 'stonehearth.services.server.player.player_service'
local AcePlayerService = class()

local log = radiant.log.create_logger('player_service')

--If the kingdom is not already specified for this player, add it now
AcePlayerService._ace_old_add_kingdom = PlayerService.add_kingdom
function AcePlayerService:add_kingdom(player_id, kingdom)
   -- removed the assert
   local pop = stonehearth.population:get_population(player_id)
   local prev_kingdom = pop:get_kingdom()
   if prev_kingdom ~= kingdom then
      if prev_kingdom then
         pop:debug_set_kingdom(kingdom)
      else
         pop:set_kingdom(kingdom)
      end
      pop:on_citizen_count_changed()

      self:_set_amenity(pop, player_id, kingdom)

      stonehearth.job:reset_jobs(player_id)
      self._sv.players[player_id].kingdom = kingdom
      self.__saved_variables:mark_changed()

      log:debug('triggering "radiant:player_kingdom_assigned" for player_id "%s"', player_id)
      radiant.events.trigger(radiant, 'radiant:player_kingdom_assigned', {player_id = player_id})
   end
end

-- return all populations which are *ACTUALLY* friendly to the specified player
function AcePlayerService:get_friendly_players(player_id)
   local players = self._friendly_players_cache[player_id]
   if not players then
      players = {}
      self._friendly_players_cache[player_id] = players
      for other_player_id, _ in pairs(self._sv.players) do
         if stonehearth.player:are_player_ids_friendly(player_id, other_player_id) then
            players[other_player_id] = true
         end
      end
   end

   return players
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
