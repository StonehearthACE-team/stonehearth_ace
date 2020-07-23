local AceFreeTimeObserver = class()

function AceFreeTimeObserver:_on_firepit_activity(e)
   if e.lit and e.player_id == radiant.entities.get_player_id(self._entity) or e.lit and radiant.entities.is_material(self._entity, 'friendly_npc') then
      self._num_fires = self._num_fires + 1
      self:_start_admiring_fire_task()
   elseif not e.lit and e.player_id == radiant.entities.get_player_id(self._entity) or not e.lit and radiant.entities.is_material(self._entity, 'friendly_npc') then
      self._num_fires = self._num_fires - 1
      if self._num_fires <= 0 then
         self:_finish_admiring()
      end
   end
end

return AceFreeTimeObserver
