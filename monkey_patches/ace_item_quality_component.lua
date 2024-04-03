local AceItemQualityComponent = class()

local NO_QUALITY = -1

function AceItemQualityComponent:destroy()
   radiant.events.trigger_async(stonehearth, 'stonehearth_ace:item_quality_removed', {
      entity_id = self._entity:get_id(),
      player_id = radiant.entities.get_player_id(self._entity),
   })
end

function AceItemQualityComponent:is_initialized()
   return self._sv.quality ~= NO_QUALITY
end

return AceItemQualityComponent
