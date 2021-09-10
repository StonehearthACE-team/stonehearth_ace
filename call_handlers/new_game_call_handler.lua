local validator = radiant.validator
local NewGameCallHandler = class()
local log = radiant.log.create_logger('new_game_call_handler')

function NewGameCallHandler:get_valid_traits_command(session, response)
   local pop_traits = stonehearth.population:get_population(session.player_id):_get_traits()
   local traits = {}
   for trait, _ in pairs(pop_traits.traits) do
      traits[trait] = true
   end
   for _, group in pairs(pop_traits.groups) do
      for trait, _ in pairs(group) do
         traits[trait] = true
      end
   end
   
   response:resolve({traits = traits})
end

function NewGameCallHandler:get_starting_rosters_command(session, response)
   _radiant.call('stonehearth_ace:get_valid_traits_command')
      :done(function(result)
            --log:debug('valid traits: %s', radiant.util.table_tostring(result))
            local rosters = radiant.mods.enum_objects('starting_rosters')
            local data = {}
            for _, name in ipairs(rosters) do
               local roster = radiant.mods.read_object('starting_rosters/' .. name)
               -- TODO: check traits against selected kingdom's traits; if any aren't valid, the roster isn't valid
               local traits_valid = true
               for _, citizen in ipairs(roster.citizens) do
                  if citizen.traits then
                     for _, trait in ipairs(citizen.traits) do
                        if not result.traits[trait] then
                           citizen.invalid_traits = true
                           traits_valid = false
                           break
                        end
                     end
                  end
               end

               if not traits_valid then
                  roster.invalid_traits = true
               end
               data[name] = roster
            end
            response:resolve({ result = data })
         end)
end

function NewGameCallHandler:delete_starting_roster_command(session, response, roster_id)
   radiant.mods.remove_object('starting_rosters/' .. roster_id)
   response:resolve({})
end

function NewGameCallHandler:save_starting_roster_command(session, response, roster_name, citizens)
   _radiant.call('stonehearth_ace:server_construct_starting_roster', roster_name, citizens)
      :done(function(result)
            radiant.mods.write_object('starting_rosters/' .. result.roster_id, result.roster)
            response:resolve({})
         end)
      :fail(function(result)
            response:reject(result)
         end)
end

function NewGameCallHandler:server_construct_starting_roster(session, response, roster_name, citizens)
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
      local roster_id = _radiant.sim.generate_uuid()
      response:resolve({roster = roster, roster_id = roster_id})
   else
      response:reject('no valid citizens')
   end
end

return NewGameCallHandler
