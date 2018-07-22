local DoodadPlacer = require 'stonehearth.services.client.build_editor.doodad_placer'
local HatchEditor = require 'services.client.build_editor.hatch_editor'
local log = radiant.log.create_logger('build_editor')
local AceDoodadPlacer = class()

AceDoodadPlacer._old_go = DoodadPlacer.go

function AceDoodadPlacer:go(session, response, uri, quality)
   local portal = radiant.entities.get_component_data(uri, 'stonehearth:portal')
   if portal and portal:is_horizontal() then
      HatchEditor(self._build_service):set_fixture_uri(uri):set_fixture_quality(quality):go(response)
   else
      self:_old_go(session, response, uri, quality)
   end
   return self
end

return AceDoodadPlacer
