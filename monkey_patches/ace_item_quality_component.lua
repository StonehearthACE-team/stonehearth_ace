local ItemQualityComponent = require 'stonehearth.components.item_quality.item_quality_component'

local AceItemQualityComponent = class()

local NO_QUALITY = -1

AceItemQualityComponent._ace_old_initialize_quality = ItemQualityComponent.initialize_quality
function AceItemQualityComponent:initialize_quality(quality, author, author_type, options)
   assert(self._sv.quality == NO_QUALITY, 'quality can only be set once on item creation')
   
   local item_quality_data = radiant.entities.get_entity_data(self._entity, 'stonehearth:item_quality', false)

   if item_quality_data then
      if item_quality_data.minimum_quality and quality < item_quality_data.minimum_quality then
         quality = item_quality_data.minimum_quality
      end

      if item_quality_data.author then
         author = item_quality_data.author
      end

      if author and not author_type and item_quality_data.author_type then
         author_type = item_quality_data.author_type
      end
   end

   self:_ace_old_initialize_quality(quality, author, author_type, options)
end

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
