local validator = radiant.validator

local AceGameCreationService = class()

-- generate citizens and make a copy of each citizen for each gender
function AceGameCreationService:generate_citizens_for_reembark_command(session, response, reembark_spec)
   validator.expect_argument_types({'table'}, reembark_spec)

   local pop = stonehearth.population:get_population(session.player_id)

   for index, citizen_spec in ipairs(reembark_spec.citizens) do
      local gender = citizen_spec.model_variant
      local role_data = { [gender] = { uri = { citizen_spec.uri } } }
      local citizen = pop:create_new_citizen_from_role_data('default', role_data, gender, {
         suppress_traits = true,
         embarking = true,
      })

      self:_apply_reembark_settings_to_citizen(citizen, citizen_spec)

      -- Replace existing.
      local generated_citizens = pop:get_generated_citizens()
      if index <= #generated_citizens then -- Skip replacement if index is out of bounds
         local citizen_entry = generated_citizens[index]
         citizen_entry.current_gender = gender
         if citizen_entry[gender] then
            radiant.entities.destroy_entity(citizen_entry[gender])
         end
         citizen_entry[gender] = citizen
      end
   end

   local final_citizens = self:_get_final_citizens(pop)

   response:resolve({ citizens = final_citizens, num_reembarked = math.min(#reembark_spec.citizens, NUM_STARTING_CITIZENS) })
end

function AceGameCreationService:_apply_reembark_settings_to_citizen(citizen, citizen_spec)
   -- Set name.
   citizen:add_component('stonehearth:unit_info'):set_custom_name(citizen_spec.name, citizen_spec.custom_data, true)
   citizen:set_debug_text(citizen_spec.name)

   -- Set attributes.
   local attributes = citizen:add_component('stonehearth:attributes')
   attributes:set_attribute('body', citizen_spec.attributes.body)
   attributes:set_attribute('spirit', citizen_spec.attributes.spirit)
   attributes:set_attribute('mind', citizen_spec.attributes.mind)

   -- Set traits.
   local traits = citizen:add_component('stonehearth:traits')
   for _, trait_uri in ipairs(citizen_spec.traits) do
      traits:add_trait(trait_uri)
   end

   -- Set jobs.
   local job = citizen:get_component('stonehearth:job')
   if citizen_spec.allowed_jobs then
      job:set_allowed_jobs(citizen_spec.allowed_jobs)
   end
   job:set_population_override(citizen_spec.population_override)
   for job_uri, level in pairs(citizen_spec.job_levels) do
      job:promote_to(job_uri, { skip_visual_effects = true, dont_drop_talisman = true })
      for _ = 1, level - 1 do
         job:level_up(true)
      end
   end
   job:promote_to(citizen_spec.current_job, { skip_visual_effects = true, dont_drop_talisman = true })

   -- Set customization.
   local customization = citizen:get_component('stonehearth:customization')
   for subcategory, style in pairs(citizen_spec.customization) do
      customization:change_customization(subcategory, style)
   end

   -- Set item preferences.
   local appeal = citizen:get_component('stonehearth:appeal')
   appeal:set_item_preferences(citizen_spec.item_preferences, citizen_spec.item_preference_discovered_flags)

   -- Set equipment.
   local equipment = citizen:get_component('stonehearth:equipment')
   for _, equipment_uri in ipairs(citizen_spec.equipment) do
      local equipment_entity = radiant.entities.create_entity(equipment_uri, { owner = session.player_id })
      equipment:equip_item(equipment_entity, true)
   end

   if citizen_spec.statistics then
      citizen:add_component('stonehearth_ace:statistics'):set_statistics(citizen_spec.statistics)
   end

   if citizen_spec.titles then
      citizen:add_component('stonehearth_ace:titles'):set_titles(citizen_spec.titles)
   end
end

return AceGameCreationService
