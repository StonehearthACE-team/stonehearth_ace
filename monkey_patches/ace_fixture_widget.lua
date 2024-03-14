local FixtureWidget = require 'stonehearth.services.client.widget.fixture_widget'
local AceFixtureWidget = class()

local log = radiant.log.create_logger('build.fixture_widget')

AceFixtureWidget._ace_old_preview_data = FixtureWidget.preview_data
function AceFixtureWidget:preview_data(data)
   self:_update_model()
   self:_ace_old_preview_data(data)
end

AceFixtureWidget._ace_old_update_data = FixtureWidget.update_data
function AceFixtureWidget:update_data(data)
   self:_update_model()
   self:_ace_old_update_data(data)
end

function AceFixtureWidget:_update_model()
   -- if there's a building widget model specified, use it
   local ap_data = radiant.entities.get_entity_data(self._entity, 'stonehearth_ace:advanced_placement')
   local model = ap_data and ap_data.placement_model
   if model then
      log:debug('%s using placement model %s', self._entity, model)
      self._entity:add_component('render_info'):set_model_variant(model)
   end
end

return AceFixtureWidget
