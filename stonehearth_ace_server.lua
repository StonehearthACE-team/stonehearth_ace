stonehearth_ace = {}

local service_creation_order = {
   'connection',
   'crafter_info',
   'water_processor',
   'water_signal',
   'mechanical',
   'persistence'
}

local monkey_patches = {
   ace_building_service = 'stonehearth.services.server.building.building_service',
   ace_charging_pedestal_component = 'stonehearth.entities.gizmos.charging_pedestal.charging_pedestal_component',
   ace_craft_order_list = 'stonehearth.components.workshop.craft_order_list',
   ace_craft_order = 'stonehearth.components.workshop.craft_order',
   ace_crafter_component = 'stonehearth.components.crafter.crafter_component',
   ace_consumption_component = 'stonehearth.components.consumption.consumption_component',
	ace_darkness_observer = 'stonehearth.ai.observers.darkness_observer',
   ace_door_component = 'stonehearth.components.door.door_component',
   ace_portal_component = 'stonehearth.components.portal.portal_component',
   ace_health_observer = 'stonehearth.ai.observers.health_observer',
   ace_job_component = 'stonehearth.components.job.job_component',
   ace_job_info_controller = 'stonehearth.services.server.job.job_info_controller',
   ace_find_equipment_upgrade_action = 'stonehearth.ai.actions.upgrade_equipment.find_equipment_upgrade_action',
   ace_town_patrol_service = 'stonehearth.services.server.town_patrol.town_patrol_service',
   ace_equipment_piece_component = 'stonehearth.components.equipment_piece.equipment_piece_component',
   ace_equipment_component = 'stonehearth.components.equipment.equipment_component',
   ace_expendable_resources_component = 'stonehearth.components.expendable_resources.expendable_resources_component',
   ace_farmer_field_component = 'stonehearth.components.farmer_field.farmer_field_component',
   ace_growing_component = 'stonehearth.components.growing.growing_component',
   ace_projectile_component = 'stonehearth.components.projectile.projectile_component',
   ace_renewable_resource_node_component = 'stonehearth.components.renewable_resource_node.renewable_resource_node_component',
   ace_resource_node_component = 'stonehearth.components.resource_node.resource_node_component',
   ace_task_tracker_component = 'stonehearth.components.task_tracker.task_tracker_component',
   ace_terrain_patch_component = 'stonehearth.components.terrain_patch.terrain_patch_component',
   ace_shepherd_pasture_component = 'stonehearth.components.shepherd_pasture.shepherd_pasture_component',
   ace_shepherd_service = 'stonehearth.services.server.shepherd.shepherd_service',
   ace_swimming_service = 'stonehearth.services.server.swimming.swimming_service',
   ace_town_service = 'stonehearth.services.server.town.town_service',
   ace_town = 'stonehearth.services.server.town.town',
   ace_evolve_component = 'stonehearth.components.evolve.evolve_component',
	ace_carry_block_component = 'stonehearth.components.carry_block.carry_block_component',
   ace_crafting_progress = 'stonehearth.components.workshop.crafting_progress',
   ace_workshop_component = 'stonehearth.components.workshop.workshop_component',
   ace_craft_items_orchestrator = 'stonehearth.services.server.town.orchestrators.craft_items_orchestrator',
   ace_collect_ingredients_orchestrator = 'stonehearth.services.server.town.orchestrators.collect_ingredients_orchestrator',
   ace_drop_carrying_in_storage_adjacent_action = 'stonehearth.ai.actions.drop_carrying_in_storage_adjacent_action',
   ace_drop_carrying_into_entity_adjacent_at = 'stonehearth.ai.actions.drop_carrying_into_entity_adjacent_at',
   ace_drop_crafting_ingredients = 'stonehearth.ai.actions.drop_crafting_ingredients',
   ace_put_another_restockable_item_into_backpack_action = 'stonehearth.ai.actions.put_another_restockable_item_into_backpack_action',
   ace_produce_crafted_items = 'stonehearth.ai.actions.produce_crafted_items',
   ace_repair_entity_adjacent_action = 'stonehearth.ai.actions.repair_entity_adjacent_action',
   ace_trapping_grounds_component = 'stonehearth.components.trapping.trapping_grounds_component',
   ace_collection_quest_shakedown = 'stonehearth.services.server.game_master.controllers.scripts.collection_quest_shakedown',
   ace_firepit_component = 'stonehearth.components.firepit.firepit_component',
	ace_lamp_component = 'stonehearth.components.lamp.lamp_component',
   ace_client_state_service = 'stonehearth.services.server.client_state.client_state_service',
   ace_client_state = 'stonehearth.services.server.client_state.client_state',
   ace_loot_drops_component = 'stonehearth.components.loot_drops.loot_drops_component',
   ace_landmark_lib = 'stonehearth.lib.landmark.landmark_lib',
   ace_loot_table = 'stonehearth.lib.loot_table.loot_table',
   ace_mining_zone_component = 'stonehearth.components.mining_zone.mining_zone_component',
   ace_incapacitation_component = 'stonehearth.components.incapacitation.incapacitation_component',
   ace_crafter_jobs_node = 'stonehearth.components.building2.plan.nodes.crafter_jobs_node',
   ace_patrollable_object = 'stonehearth.services.server.town_patrol.patrollable_object',
   ace_get_patrol_route_action = 'stonehearth.ai.actions.get_patrol_route_action',
   ace_party_component = 'stonehearth.components.party.party_component',
   ace_player_service = 'stonehearth.services.server.player.player_service',
   ace_water_component = 'stonehearth.components.water.water_component',
   ace_waterfall_component = 'stonehearth.components.waterfall.waterfall_component',
   ace_commands_component = 'stonehearth.components.commands.commands_component',
   ace_trapper = 'stonehearth.jobs.trapper.trapper',
	ace_geomancer = 'stonehearth.jobs.geomancer.geomancer',
   ace_storage_component = 'stonehearth.components.storage.storage_component',
   ace_buffs_component = 'stonehearth.components.buffs.buffs_component',
   ace_buff = 'stonehearth.components.buffs.buff',
   ace_farmer = 'stonehearth.jobs.farmer.farmer',
   ace_herbalist = 'stonehearth.jobs.herbalist.herbalist',
   ace_shepherd = 'stonehearth.jobs.shepherd.shepherd',
   ace_heal_target = 'stonehearth.entities.consumables.scripts.heal_target',
   ace_farming_task_group = 'stonehearth.ai.task_groups.farming_task_group',
   ace_herding_task_group = 'stonehearth.ai.task_groups.herding_task_group',
   ace_harvest_crop_adjacent = 'stonehearth.ai.actions.harvest_crop_adjacent',
   ace_inventory_tracker = 'stonehearth.services.server.inventory.inventory_tracker',
   ace_dig_adjacent_action = 'stonehearth.ai.actions.mining.dig_adjacent_action',
   ace_eat_feed_adjacent_action = 'stonehearth.ai.actions.pasture_animal.eat_feed_adjacent_action',
   ace_plant_field_adjacent_action = 'stonehearth.ai.actions.plant_field_adjacent_action',
   ace_posture_component = 'stonehearth.components.posture.posture_component',
   ace_effect_manager = 'radiant.modules.effects.effect_manager',
   ace_entities = 'radiant.modules.entities',
   ace_util = 'radiant.lib.util',
   ace_inventory = 'stonehearth.services.server.inventory.inventory',
   ace_restock_director = 'stonehearth.services.server.inventory.restock_director',
   ace_farming_service = 'stonehearth.services.server.farming.farming_service',
   ace_food_decay_service = 'stonehearth.services.server.food_decay.food_decay_service',
   ace_hydrology_service = 'stonehearth.services.server.hydrology.hydrology_service',
	ace_free_time_observer = 'stonehearth.ai.observers.free_time_observer',
   ace_find_best_reachable_entity_by_type = 'stonehearth.ai.actions.find_best_reachable_entity_by_type',
   ace_find_entity_type_in_storage_action = 'stonehearth.ai.actions.find_entity_type_in_storage_action',
   --ace_place_carrying_on_structure_adjacent_action = 'stonehearth.ai.actions.place_carrying_on_structure_adjacent_action',
   ace_terrain_service = 'stonehearth.services.server.terrain.terrain_service',
   ace_trapping_service = 'stonehearth.services.server.trapping.trapping_service',
   ace_weather_state = 'stonehearth.services.server.weather.weather_state',
   ace_weather_service = 'stonehearth.services.server.weather.weather_service',
   ace_seasons_service = 'stonehearth.services.server.seasons.seasons_service',
   ace_world_generation_service = 'stonehearth.services.server.world_generation.world_generation_service',
   ace_unit_info_component = 'stonehearth.components.unit_info.unit_info_component',
   ace_relations = 'stonehearth.lib.player.relations',
   ace_aggro_observer = 'stonehearth.ai.observers.aggro_observer',
   ace_sleepiness_observer = 'stonehearth.ai.observers.sleepiness_observer',
   ace_kill_at_zero_health_observer = 'stonehearth.ai.observers.kill_at_zero_health_observer',
   ace_job_service = 'stonehearth.services.server.job.job_service',
   ace_constants = 'stonehearth.constants',
   ace_shared_filters = 'stonehearth.ai.filters.shared_filters',
   ace_eating_lib = 'stonehearth.ai.lib.eating_lib',
   ace_food_preference_script = 'stonehearth.data.traits.food_preference.food_preference_script',
   ace_stacks_component = 'stonehearth.components.stacks.stacks_component',
   ace_game_creation_service = 'stonehearth.services.server.game_creation.game_creation_service',
   ace_unlock_recipe_encounter = 'stonehearth.services.server.game_master.controllers.encounters.unlock_recipe_encounter',
   ace_reembarkation_encounter = 'stonehearth.services.server.game_master.controllers.encounters.reembarkation_encounter',
   ace_donation_encounter = 'stonehearth.services.server.game_master.controllers.encounters.donation_encounter',
   ace_donation_dialog_encounter = 'stonehearth.services.server.game_master.controllers.encounters.donation_dialog_encounter',
   ace_returning_trader_script = 'stonehearth.services.server.game_master.controllers.script_encounters.returning_trader_script',
   ace_simple_caravan_script = 'stonehearth.services.server.game_master.controllers.script_encounters.simple_caravan_script',
   ace_combat_service = 'stonehearth.services.server.combat.combat_service',
   ace_combat_server_commands_service = 'stonehearth.services.server.combat_server_commands.combat_server_commands_service',
   ace_game_master_lib = 'stonehearth.lib.game_master.game_master_lib',
   ace_population_faction = 'stonehearth.services.server.population.population_faction',
   ace_entities_call_handler = 'stonehearth.call_handlers.entities_call_handler',
   ace_farming_call_handler = 'stonehearth.call_handlers.farming_call_handler',
   ace_resource_call_handler = 'stonehearth.call_handlers.resource_call_handler',
   ace_periodic_health_modification = 'stonehearth.data.buffs.scripts.periodic_health_modification',
	ace_aura_buff = 'stonehearth.data.buffs.scripts.aura_buff',
   ace_tentacle_snared_debuff = 'stonehearth.data.buffs.tentacle_snared.tentacle_snared_debuff',
   ace_trait = 'stonehearth.components.traits.trait',
   ace_animal_companion_script = 'stonehearth.data.traits.animal_companion.animal_companion_script',
   ace_bulletin = 'stonehearth.services.server.bulletin_board.bulletin',
   ace_memorialize_death_action = 'stonehearth.ai.actions.memorialize_death_action',
   ace_get_food_from_container_adjacent = 'stonehearth.ai.actions.get_food_from_container_adjacent',
   ace_check_bait_trap_adjacent_action = 'stonehearth.ai.actions.trapping.check_bait_trap_adjacent_action',
   ace_bait_trap_component = 'stonehearth.components.trapping.bait_trap_component',
   ace_ai_component = 'stonehearth.components.ai.ai_component',
   ace_personality_component = 'stonehearth.components.personality.personality_component',
   ace_pet_component = 'stonehearth.components.pet.pet_component',
   ace_csg_lib = 'stonehearth.lib.csg.csg_lib',
   ace_find_healable_target_observer = 'stonehearth.ai.observers.find_healable_target_observer',
   ace_safety_observer = 'stonehearth.ai.observers.safety_observer',
   ace_cleric = 'stonehearth.jobs.cleric.cleric',
   ace_encounter = 'stonehearth.services.server.game_master.controllers.encounter',
   ace_collect_starting_resources = 'stonehearth.scenarios.quests.collect_starting_resources.collect_starting_resources',
   ace_pillage_mission = 'stonehearth.services.server.game_master.controllers.missions.pillage_mission',
   ace_raid_crops_mission = 'stonehearth.services.server.game_master.controllers.missions.raid_crops_mission',
   ace_raid_stockpiles_mission = 'stonehearth.services.server.game_master.controllers.missions.raid_stockpiles_mission',
   ace_spawn_enemies_mission = 'stonehearth.services.server.game_master.controllers.missions.spawn_enemies_mission',
   ace_wander_mission = 'stonehearth.services.server.game_master.controllers.missions.wander_mission',
   ace_guildmaster_town_bonus = 'stonehearth.data.town_bonuses.guildmaster_town_bonus',
   ace_player_jobs_controller = 'stonehearth.services.server.job.player_jobs_controller',
	ace_scenario_modder_services = 'stonehearth.services.server.static_scenario.scenario_modder_services'
}

local function monkey_patching()
   for from, into in pairs(monkey_patches) do
      local monkey_see = require('monkey_patches.' .. from)
      local monkey_do = radiant.mods.require(into)
      radiant.log.write_('stonehearth_ace', 0, 'ACE server monkey-patching sources \'' .. from .. '\' => \'' .. into .. '\'')
      --radiant.log.write_('stonehearth_ace', 0, 'ACE server monkey-patching data \'' .. tostring(monkey_see) .. '\' => \'' .. tostring(monkey_do) .. '\'')
      if monkey_see.ACE_USE_MERGE_INTO_TABLE then
         -- use merge_into_table to also mixin other values, not just functions
         radiant.util.merge_into_table(monkey_do, monkey_see)
      else
         radiant.mixin(monkey_do, monkey_see)
      end
   end
end

local function create_service(name)
   local path = string.format('services.server.%s.%s_service', name, name)
   local service = require(path)()

   local saved_variables = stonehearth_ace._sv[name]
   if not saved_variables then
      saved_variables = radiant.create_datastore()
      stonehearth_ace._sv[name] = saved_variables
   end

   service.__saved_variables = saved_variables
   service._sv = saved_variables:get_data()
   saved_variables:set_controller(service)
   saved_variables:set_controller_name('stonehearth_ace:' .. name)
   service:initialize()
   stonehearth_ace[name] = service
end

function stonehearth_ace:_on_init()
   stonehearth_ace._sv = stonehearth_ace.__saved_variables:get_data()

   self:_run_scripts('pre_ace_services')

   for _, name in ipairs(service_creation_order) do
      create_service(name)
   end

   radiant.events.trigger_async(radiant, 'stonehearth_ace:server:init')
   radiant.log.write_('stonehearth_ace', 0, 'ACE server initialized')
end

function stonehearth_ace:_on_required_loaded()
   monkey_patching()

   self:_run_scripts('post_monkey_patching')
   
   radiant.events.trigger_async(radiant, 'stonehearth_ace:server:required_loaded')
end

function stonehearth_ace:_get_scripts_to_load()
   if not self.load_scripts then
      self.load_scripts = radiant.resources.load_json('stonehearth_ace/scripts/server_load_scripts.json')
   end
   return self.load_scripts
end

function stonehearth_ace:_run_scripts(category)
   local scripts = self:_get_scripts_to_load()
   if category and scripts[category] then
      for script, run in pairs(scripts[category]) do
         if run then
            local s = require(script)
            if s then
               s()
            end
         end
      end
   end
end

radiant.events.listen(stonehearth_ace, 'radiant:init', stonehearth_ace, stonehearth_ace._on_init)
radiant.events.listen(radiant, 'radiant:required_loaded', stonehearth_ace, stonehearth_ace._on_required_loaded)

return stonehearth_ace
