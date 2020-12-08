local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local validator = radiant.validator
local constants = require 'stonehearth.constants'
local NUM_STARTING_CITIZENS = constants.game_creation.num_starting_citizens
local MIN_STARTING_ITEM_RADIUS = 0
local MIN_STARTING_ITEM_CONTAINER_RADIUS = 6
local MAX_STARTING_ITEM_RADIUS = 5
local MAX_STARTING_ITEM_CONTAINER_RADIUS = 8

local GameCreationService = require 'stonehearth.services.server.game_creation.game_creation_service'
local AceGameCreationService = class()

AceGameCreationService._ace_old_embark_command = GameCreationService.embark_command
function AceGameCreationService:embark_command(session, response)
   radiant.events.trigger(radiant, 'stonehearth_ace:player_embarked', {player_id = session.player_id})
   return self:_ace_old_embark_command(session, response)
end

-- ACE: moved starting the game master for this player to the end of the function instead of the middle
function AceGameCreationService:create_camp_command(session, response, pt)
   validator.expect_argument_types({'table'}, pt)
   validator.expect.table.fields({'x', 'y', 'z'}, pt)

   if validator.is_host_player(session) then
      stonehearth.calendar:start()
      stonehearth.hydrology:start()
      stonehearth.mining:start()
   end

   stonehearth.world_generation:set_starting_location(Point2(pt.x, pt.z))

   local facing = 180
   local player_id = session.player_id
   local town = stonehearth.town:get_town(player_id)
   local pop = stonehearth.population:get_population(player_id)
   local random_town_name = town:get_town_name()
   local inventory = stonehearth.inventory:get_inventory(player_id)

   -- place the stanfard in the middle of the camp
   local location = Point3(pt.x, pt.y, pt.z)

   local standard, standard_ghost = stonehearth.player:get_kingdom_banner_style(session.player_id)
   if not standard then
      standard = 'stonehearth:camp_standard'
   end

   local banner_entity = radiant.entities.create_entity(standard, { owner = player_id })
   radiant.terrain.place_entity(banner_entity, location, { facing = facing, force_iconic = false })
   inventory:add_item(banner_entity)
   town:set_banner(banner_entity)

   -- build the camp
   local camp_x = pt.x
   local camp_z = pt.z

   local citizen_locations = {
      {x=camp_x-3, z=camp_z-3},
      {x=camp_x+0, z=camp_z-3},
      {x=camp_x+3, z=camp_z-3},
      {x=camp_x-3, z=camp_z+3},
      {x=camp_x+3, z=camp_z+3},
      {x=camp_x-3, z=camp_z+0},
      {x=camp_x+3, z=camp_z+0},
   }

   if next(pop:get_generated_citizens()) == nil then
      -- for quick start. TODO: make quick start integrate existing starting flow so we don't need to do this
      self:_generate_initial_roster(pop)
   end

   -- get final citizens and destroy gender entity copies
   local final_citizens = self:_get_final_citizens(pop, true)

   local index = 1
   local min_radius = 3
   local max_radius = 7
   local min_y = location.y - max_radius
   for _, citizen in pairs(final_citizens) do
      local citizen_location = citizen_locations[index]
      if not citizen_location then
         citizen_location = radiant.terrain.find_placement_point(location, min_radius, max_radius, citizen, 1, false)
      end
      self:_place_citizen_embark(citizen, citizen_location.x, citizen_location.z, { facing = facing, min_y = min_y })
      index = index + 1
   end

   pop:unset_generated_citizens()

   local town =  stonehearth.town:get_town(player_id)
   town:check_for_combat_job_presence()

   local camp_hearth_uri = pop:get_hearth() or 'stonehearth:decoration:firepit_hearth'
   local hearth = self:_place_item(pop, camp_hearth_uri, camp_x, camp_z+5, { facing = facing, force_iconic = false, min_y = min_y })
   inventory:add_item(hearth)
   town:set_hearth(hearth)

   local game_options = pop:get_game_options()

   if validator.is_host_player(session) then
      -- Open game to remote players if specified
      if game_options.remote_connections_enabled then
         stonehearth.session_server:set_remote_connections_enabled(true)
      end

      -- Set max number of remote players if specified
      if game_options.max_players then
         stonehearth.session_server:set_max_players(game_options.max_players)
      end

      -- Set whether clients can control game speed
      if game_options.game_speed_anarchy_enabled then
         stonehearth.game_speed:set_anarchy_enabled(game_options.game_speed_anarchy_enabled)
      end
   end

   if game_options.starting_items_container then
      -- if a uri is being supplied, create the entity, otherwise assume it's already an entity
      local starting_items_container = type(game_options.starting_items_container) == 'string' and
            radiant.entities.create_entity(game_options.starting_items_container, {owner = player_id}) or game_options.starting_items_container
      
      -- if it hasn't already been placed, find a place for it
      if not radiant.entities.get_world_grid_location(starting_items_container) then
			local placement_location = Point3(camp_x, pt.y, camp_z-6)
			radiant.terrain.place_entity(starting_items_container, placement_location, { force_iconic = false, facing = 90 })
      end
      starting_items_container:add_component('stonehearth_ace:input')
      town:add_default_storage(starting_items_container)
   end

   local default_storage = town:get_default_storage()

   -- Spawn initial items
   local starting_item_uris = radiant.shallow_copy(game_options.starting_items)  -- probably don't need to actually copy this
   local starting_resource = stonehearth.player:get_kingdom_starting_resource(player_id) or 'stonehearth:resources:wood:oak_log'
   starting_item_uris[starting_resource] = (starting_item_uris[starting_resource] or 0) + 2

   local starting_items = radiant.entities.output_items(game_options.starting_items, location,
      MIN_STARTING_ITEM_RADIUS, MAX_STARTING_ITEM_RADIUS, { owner = player_id }, nil, default_storage, true).spilled

   -- add all the spawned items to the inventory, have citizens pick up any spilled items
   local i = 1
   for id, item in pairs(starting_items) do
      inventory:add_item(item)
      if i <= NUM_STARTING_CITIZENS then
         radiant.entities.pickup_item(final_citizens[i], item)
         i = i + 1
      else
         break
      end
   end

   -- kickstarter pets
   if game_options.starting_pets then
       for i, pet_uri in ipairs (game_options.starting_pets) do
          local x_offset = -6 + i * 3;
          self:_place_pet(pop, pet_uri, camp_x-x_offset, camp_z-6, { facing = facing })
       end
   end

   -- Add starting gold
   local starting_gold = game_options.starting_gold
   if (starting_gold > 0) then
      local inventory = stonehearth.inventory:get_inventory(player_id)
      inventory:add_gold(starting_gold)
   end

   -- Handle re-embarkation
   if game_options.reembark_spec then
      -- Add items.
      for _, item_spec in ipairs(game_options.reembark_spec.items) do
         if item_spec.uri == 'stonehearth:loot:gold' then
            inventory:add_gold(stonehearth.constants.reembarkation.gold_per_bag * item_spec.count)
         else
            local uri_exists = radiant.resources.load_json(item_spec.uri, true, false) ~= nil
            if uri_exists then
               local spawned_items = radiant.entities.output_items({ [item_spec.uri] = {[item_spec.item_quality or 1] = item_spec.count } }, location,
                  MIN_STARTING_ITEM_RADIUS, MAX_STARTING_ITEM_RADIUS, { owner = player_id }, nil, default_storage, true).spilled
               for _, item in pairs(spawned_items) do
                  inventory:add_item(item)
               end
            end
         end
      end

      -- Unlock recipes.
      for job_uri, recipe_keys in pairs(game_options.reembark_spec.recipes) do
         local job_info = stonehearth.job:get_job_info(player_id, job_uri)
         if job_info then  -- In case it was from a mod.
            for _, recipe_key in ipairs(recipe_keys) do
               if job_uri == 'stonehearth:jobs:farmer' then
                  job_info:manually_unlock_crop(recipe_key, true)
               else
                  job_info:manually_unlock_recipe(recipe_key, true)
               end
            end
         end
      end
   end

   stonehearth.terrain:set_fow_enabled(player_id, true)

   -- save that the camp has been placed
   pop:place_camp()
   
   -- ACE: just moved this down here so everything else (especially reembarkation stuff) happens first
   stonehearth.game_master:get_game_master(player_id):start()

   return {random_town_name = random_town_name}
end

-- generate citizens and make a copy of each citizen for each gender
function AceGameCreationService:generate_citizens_for_reembark_command(session, response, reembark_spec)
   validator.expect_argument_types({'table'}, reembark_spec)

   local pop = stonehearth.population:get_population(session.player_id)
   local kingdom = pop:get_kingdom()

   for index, citizen_spec in ipairs(reembark_spec.citizens) do
      local gender = citizen_spec.model_variant
      local role_data = { [gender] = { uri = { citizen_spec.uri } } }
      local citizen = pop:create_new_citizen_from_role_data('default', role_data, gender, {
         suppress_traits = true,
         embarking = true,
      })

      self:_apply_reembark_settings_to_citizen(session, kingdom, citizen, citizen_spec)

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

function AceGameCreationService:_apply_reembark_settings_to_citizen(session, kingdom, citizen, citizen_spec)
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
   -- set population override if it's a different population than this kingdom
   local population_override = citizen_spec.population_override
   if population_override ~= '' and population_override ~= kingdom then
      job:set_population_override(population_override)
   end
   if citizen_spec.job_levels then
      for job_uri, level in pairs(citizen_spec.job_levels) do
         job:promote_to(job_uri, { skip_visual_effects = true, dont_drop_talisman = true })
         for _ = 1, level - 1 do
            job:level_up(true)
         end
      end
   end
   if citizen_spec.current_job then
      job:promote_to(citizen_spec.current_job, { skip_visual_effects = true, dont_drop_talisman = true })
   end

   -- Set customization.
   local customization = citizen:get_component('stonehearth:customization')
   for subcategory, style in pairs(citizen_spec.customization) do
      customization:change_customization(subcategory, style)
   end

   -- Set item preferences.
   if citizen_spec.item_preferences then
      local appeal = citizen:get_component('stonehearth:appeal')
      appeal:set_item_preferences(citizen_spec.item_preferences, citizen_spec.item_preference_discovered_flags)
   end

   -- Set equipment.
   if citizen_spec.equipment then
      local equipment = citizen:get_component('stonehearth:equipment')
      for _, equipment_uri in ipairs(citizen_spec.equipment) do
         local equipment_data = radiant.util.is_string(equipment_uri) and {uri = equipment_uri} or equipment_uri
         local equipment_entity = radiant.entities.create_entity(equipment_data.uri, { owner = session.player_id })
         self:_set_customizable_entity_data(equipment_entity, equipment_data)

         equipment:equip_item(equipment_entity, true)
      end
   end

	self:_set_customizable_entity_data(citizen, citizen_spec)
end

function AceGameCreationService:_set_customizable_entity_data(entity, data)
   -- Set name.
   if data.name then
      entity:add_component('stonehearth:unit_info'):set_custom_name(data.name, data.custom_data, true)
   end

   -- Set Statistics
   if data.statistics then
      entity:add_component('stonehearth_ace:statistics'):set_statistics(data.statistics)
   end

   -- Set Titles
   if data.titles then
      entity:add_component('stonehearth_ace:titles'):set_titles(data.titles)
   end

   -- Set Buffs
   if data.buffs then
      local buffs = entity:add_component('stonehearth:buffs')
      for buff_uri, options in pairs(data.buffs) do
         buffs:add_buff(buff_uri, options)
      end
   end
end

return AceGameCreationService
