local AceRenderer = class()
local log = radiant.log.create_logger('renderer')

local SHOW_GRIDLINES = radiant.util.get_global_config('mods.stonehearth.show_gridlines', false)

function AceRenderer:set_ui_mode(ui_mode)
   if self._ui_mode ~= ui_mode then
      self._ui_mode = ui_mode
      if ui_mode == 'normal' and not SHOW_GRIDLINES then
         _radiant.renderer.draw_gridlines(false)
      elseif ui_mode == 'hud' or ui_mode == 'build' or ui_mode == 'military' then
         _radiant.renderer.draw_gridlines(true)
      end
      radiant.events.trigger_async(radiant, 'stonehearth:ui_mode_changed')
   end
end

return AceRenderer
