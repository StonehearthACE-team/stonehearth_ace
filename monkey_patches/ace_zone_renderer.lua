local AceZoneRenderer = class()

local log = radiant.log.create_logger('zone_renderer')

function AceZoneRenderer:_set_ghost_mode(render_entity, ghost_mode)
   if ghost_mode then
      local material = render_entity:get_material_path('hud')
      render_entity:set_material_override(material)
   else
      render_entity:set_material_override('')
   end

   local selectable = not ghost_mode
   stonehearth.selection:set_selectable(render_entity:get_entity(), selectable, false)
end

return AceZoneRenderer
