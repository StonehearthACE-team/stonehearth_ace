local AceSafetyScoreObserver = class()

--If an entity from our population was killed, lower safety score
function AceSafetyScoreObserver:_on_entity_killed(e)
   -- Check to see if what was killed was something we should write about....
   -- Not TODO: psychopathy?
   if not e.sentient then
      return
   end

   if e.player_id and e.player_id == radiant.entities.get_player_id(self._sv._entity) then
      --Pass in name of the dead friend into the journal entry
      local personality_component = self._sv._entity:get_component('stonehearth:personality')

      local substitution_values = {}
      substitution_values['dead_friend_display_name'] = e.display_name
      substitution_values['dead_friend_custom_name'] = e.custom_name
      substitution_values['dead_friend_custom_data'] = e.custom_data -- Paul: added this for proper localization of names/titles

      local journal_data = {entity = self._sv._entity, description = 'villager_death', tags = {'safety', 'combat', 'villager_death'}, substitutions=substitution_values}
      self._score_component:change_score('safety', stonehearth.constants.score.safety.TOWN_DEATH, journal_data)

      --Keep track of this so we know whether we can run the "no activity today" perk, otherwise, can trigger multiple times each day
      self._sv.friend_died_today = true
   end
end

return AceSafetyScoreObserver
