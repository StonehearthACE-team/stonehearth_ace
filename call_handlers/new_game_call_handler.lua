local validator = radiant.validator
local NewGameCallHandler = class()

function NewGameCallHandler:get_starting_rosters_command(session, response)
   local rosters = radiant.mods.enum_objects('starting_rosters')
   local result = {}
   for _, name in ipairs(rosters) do
      result[name] = radiant.mods.read_object('starting_rosters/' .. name)
   end
   response:resolve({ result = result })
end

function NewGameCallHandler:delete_starting_roster_command(session, response, roster_id)
   radiant.mods.remove_object('starting_rosters/' .. roster_id)
   response:resolve({})
end

function NewGameCallHandler:save_starting_roster_command(session, response, roster_name, citizens)
   local roster_id, roster = self:_construct_starting_roster_record(roster_name, citizens)

   if roster_id and roster then
      radiant.mods.write_object('starting_rosters/' .. roster_id, roster)
      response:resolve({})
   else
      response:reject({})
   end
end

function NewGameCallHandler:_construct_starting_roster_record(roster_name, citizens)
   local roster = { citizens = {}, name = roster_name }

   for _, citizen in pairs(citizens) do
      validator.assert_type(citizen, 'Entity')

      local attributes = {
         mind = citizen:get_component('stonehearth:attributes'):get_attribute('mind'),
         body = citizen:get_component('stonehearth:attributes'):get_attribute('body'),
         spirit = citizen:get_component('stonehearth:attributes'):get_attribute('spirit'),
      }

      local model_variant = citizen:get_component('render_info'):get_model_variant()  -- Gender
      if model_variant == '' then
         model_variant = stonehearth.constants.population.DEFAULT_GENDER
      end

      local customization_styles = {}
      for _, style in pairs(citizen:get_component('stonehearth:customization'):get_added_styles()) do
         customization_styles[style.subcategory] = style.style
      end

      local traits = citizen:get_component('stonehearth:traits'):get_traits()
      local trait_icons = {}
      for _, trait in pairs(traits) do
         table.insert(trait_icons, trait:get_icon())
      end

      table.insert(roster.citizens, {
         name = citizen:get_component('stonehearth:unit_info'):get_custom_name(),
         uri = citizen:get_uri(),
         model_variant = model_variant,
         customization = customization_styles,
         attributes = attributes,
         traits = radiant.keys(traits),
         trait_icons = trait_icons,
         current_job = stonehearth.player:get_default_base_job(radiant.entities.get_player_id(citizen)),
      })
   end

   if #roster.citizens > 0 then
      return _radiant.sim.generate_uuid(), roster
   end
end

return NewGameCallHandler
