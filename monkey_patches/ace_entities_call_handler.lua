local validator = radiant.validator

local AceEntityCallHandler = class()

function AceEntityCallHandler:set_custom_name(session, response, entity, name, set_custom_name)
   validator.expect_argument_types({'Entity', 'string', validator.optional('boolean')}, entity, name, set_custom_name)
   validator.expect.matching_player_id(session.player_id, entity)

   local custom_name_component = entity:add_component('stonehearth:unit_info')

   -- this part should get handled by the unit info component (for titles)
   -- if set_custom_name==nil or set_custom_name then
   --    custom_name_component:set_display_name('i18n(stonehearth:ui.game.entities.custom_name)')
   -- end
   custom_name_component:set_custom_name(name)
   return true
end

return AceEntityCallHandler
