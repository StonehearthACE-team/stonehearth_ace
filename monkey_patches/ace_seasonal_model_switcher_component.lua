local AceSeasonalModelSwitcherComponent = class()

local log = radiant.log.create_logger('seasonal_model_switcher')

function AceSeasonalModelSwitcherComponent:get_last_applied_variant()
   return self._sv._last_applied_variant
end

function AceSeasonalModelSwitcherComponent:_update(transition)
   if self._current_season == transition.to then
      return  -- Already switched.
   elseif transition.t < self._sv.switch_t then
      if not self._current_season then
         self._current_season = transition.from
      end
      return  -- Not yet.
   elseif stonehearth.calendar:is_daytime() and transition.t < 1 then
      return  -- Try to swap at night, as long as it's not the final transition.
   end
   
   self._current_season = transition.to
   
   local biome_uri = stonehearth.world_generation:get_biome_alias()
   local biome_seasons = self._json[biome_uri] or self._json['*']
   if not biome_seasons then
      return
   end

   local new_variant = biome_seasons[self._current_season]
   if new_variant and new_variant ~= self._sv._last_applied_variant then
      self._sv._last_applied_variant = new_variant
      local render_info = self._entity:get('render_info')
      local curr_model_variant = render_info:get_model_variant()
      if curr_model_variant ~= 'depleted' and curr_model_variant ~= 'half_renewed' then
         render_info:set_model_variant(new_variant)
      end
   end
end

return AceSeasonalModelSwitcherComponent
