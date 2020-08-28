local AceFreeTimeObserver = class()

function AceFreeTimeObserver:_on_firepit_activity(e)
   if e.player_id == radiant.entities.get_player_id(self._entity) or radiant.entities.is_material(self._entity, 'friendly_npc') then
      if e.lit then
         self._num_fires = self._num_fires + 1
         self:_start_admiring_fire_task()
      else
         self._num_fires = self._num_fires - 1
         if self._num_fires <= 0 then
            self:_finish_admiring()
         end
      end
   end
end

return AceFreeTimeObserver
