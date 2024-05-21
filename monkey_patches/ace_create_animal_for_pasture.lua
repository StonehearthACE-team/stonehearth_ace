local AceCreateAnimalForPasture = radiant.class()

function AceCreateAnimalForPasture:_find_spawn_location()
   local player_id = radiant.entities.get_player_id(self._entity)
   assert(not self._searcher)
   self._searcher = radiant.create_controller(
         'stonehearth:game_master:util:choose_location_outside_town',
         20, 64,
         function(op, location)
            return self:_find_location_callback(op, location)
         end,
         nil, player_id, true, { dirt = true, grass = true })
end

return AceCreateAnimalForPasture
