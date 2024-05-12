stonehearth_ace = {}

local service_creation_order = {
   'connection',
   'crafter_info',
   'mechanical',
   'mercantile',
   'persistence',
   'universal_storage',
   --'water_processor', -- functionality rolled into hydrology service
   'water_signal',
}

local monkey_patches = {
   ace_aggro_observer = 'stonehearth.ai.observers.aggro_observer',
   ace_ai_component = 'stonehearth.components.ai.ai_component',
   ace_ai_service = 'stonehearth.services.server.ai.ai_service',
   ace_animal_companion_script = 'stonehearth.data.traits.animal_companion.animal_companion_script',
   ace_attack_melee_adjacent_action = 'stonehearth.ai.actions.combat.attack_melee_adjacent_action',
   ace_attack_ranged_action = 'stonehearth.ai.actions.combat.attack_ranged_action',
   ace_attributes_component = 'stonehearth.components.attributes.attributes_component',
   ace_aura_buff = 'stonehearth.data.buffs.scripts.aura_buff',
   ace_bait_trap_component = 'stonehearth.components.trapping.bait_trap_component',
   ace_basic_inventory_tracker_controller = 'stonehearth.services.server.inventory.basic_inventory_tracker_controller',
   ace_blueprint_job = 'stonehearth.components.building2.plan.jobs.blueprint_job',
   ace_blueprints_to_building_pieces_job = 'stonehearth.components.building2.plan.jobs.blueprints_to_building_pieces_job',
   ace_buff = 'stonehearth.components.buffs.buff',
   ace_buffs_component = 'stonehearth.components.buffs.buffs_component',
   ace_build_util = 'stonehearth.lib.build_util',
   ace_building = 'stonehearth.components.building2.building',
   ace_building_destruction_job = 'stonehearth.components.building2.building_destruction_job',
   ace_building_monitor = 'stonehearth.components.building2.building_monitor',
   ace_building_piece_dependencies_job = 'stonehearth.components.building2.plan.jobs.building_piece_dependencies_job',
   ace_building_service = 'stonehearth.services.server.building.building_service',
   ace_bulletin = 'stonehearth.services.server.bulletin_board.bulletin',
   ace_calendar_call_handler = 'stonehearth.call_handlers.calendar_call_handler',
   ace_calendar_service = 'stonehearth.services.server.calendar.calendar_service',
   ace_carry_block_component = 'stonehearth.components.carry_block.carry_block_component',
   ace_channel_manager = 'stonehearth.services.server.hydrology.channel_manager',
   ace_charging_pedestal_component = 'stonehearth.entities.gizmos.charging_pedestal.charging_pedestal_component',
   ace_check_bait_trap_adjacent_action = 'stonehearth.ai.actions.trapping.check_bait_trap_adjacent_action',
   ace_check_stuck_when_idle_action = 'stonehearth.ai.actions.check_stuck_when_idle_action',
   ace_chunk = 'stonehearth.components.building2.plan.chunk',
   ace_cleric = 'stonehearth.jobs.cleric.cleric',
   ace_client_state = 'stonehearth.services.server.client_state.client_state',
   ace_client_state_service = 'stonehearth.services.server.client_state.client_state_service',
   ace_collect_ingredients_orchestrator = 'stonehearth.services.server.town.orchestrators.collect_ingredients_orchestrator',
   ace_collect_starting_resources = 'stonehearth.scenarios.quests.collect_starting_resources.collect_starting_resources',
   ace_collection_quest_encounter = 'stonehearth.services.server.game_master.controllers.encounters.collection_quest_encounter',
   ace_collection_quest_shakedown = 'stonehearth.services.server.game_master.controllers.scripts.collection_quest_shakedown',
   ace_combat_server_commands_service = 'stonehearth.services.server.combat_server_commands.combat_server_commands_service',
   ace_combat_service = 'stonehearth.services.server.combat.combat_service',
   ace_combat_state_component = 'stonehearth.components.combat_state.combat_state_component',
   ace_commands_component = 'stonehearth.components.commands.commands_component',
   ace_constants = 'stonehearth.constants',
   ace_consumption_component = 'stonehearth.components.consumption.consumption_component',
   ace_conversation_manager = 'stonehearth.services.server.conversation.conversation_manager',
   ace_craft_items_orchestrator = 'stonehearth.services.server.town.orchestrators.craft_items_orchestrator',
   ace_craft_order = 'stonehearth.components.workshop.craft_order',
   ace_craft_order_list = 'stonehearth.components.workshop.craft_order_list',
   ace_crafter_component = 'stonehearth.components.crafter.crafter_component',
   ace_crafter_jobs_node = 'stonehearth.components.building2.plan.nodes.crafter_jobs_node',
   ace_crafting_progress = 'stonehearth.components.workshop.crafting_progress',
   ace_create_mission_encounter = 'stonehearth.services.server.game_master.controllers.encounters.create_mission_encounter',
   ace_csg_lib = 'stonehearth.lib.csg.csg_lib',
   ace_customization_component = 'stonehearth.components.customization.customization_component',
   ace_daily_report_script = 'stonehearth.data.gm.campaigns.game_events.arcs.trigger.game_events.encounters.daily_report_script',
   ace_darkness_observer = 'stonehearth.ai.observers.darkness_observer',
   ace_debugtools_commands = 'debugtools.call_handlers.debugtools_commands',
   ace_default_conversation_script = 'stonehearth.data.conversation.default.default_conversation_script',
   ace_defend_melee_action = 'stonehearth.ai.actions.combat.defend_melee_action',
   ace_delivery_quest_encounter = 'stonehearth.services.server.game_master.controllers.encounters.delivery_quest_encounter',
   ace_dig_adjacent_action = 'stonehearth.ai.actions.mining.dig_adjacent_action',
   ace_donation_dialog_encounter = 'stonehearth.services.server.game_master.controllers.encounters.donation_dialog_encounter',
   ace_donation_encounter = 'stonehearth.services.server.game_master.controllers.encounters.donation_encounter',
   ace_door_component = 'stonehearth.components.door.door_component',
   ace_drop_carrying_in_storage_adjacent_action = 'stonehearth.ai.actions.drop_carrying_in_storage_adjacent_action',
   ace_drop_carrying_into_entity_adjacent_at = 'stonehearth.ai.actions.drop_carrying_into_entity_adjacent_at',
   ace_drop_carrying_when_idle_action = 'stonehearth.ai.actions.drop_carrying_when_idle_action',
   ace_drop_crafting_ingredients = 'stonehearth.ai.actions.drop_crafting_ingredients',
   ace_eat_feed_adjacent_action = 'stonehearth.ai.actions.pasture_animal.eat_feed_adjacent_action',
   ace_eating_lib = 'stonehearth.ai.lib.eating_lib',
   ace_effect_manager = 'radiant.modules.effects.effect_manager',
   ace_encounter = 'stonehearth.services.server.game_master.controllers.encounter',
   ace_entities = 'radiant.modules.entities',
   ace_entities_call_handler = 'stonehearth.call_handlers.entities_call_handler',
   ace_entity_forms_component = 'stonehearth.components.entity_forms.entity_forms_component',
   ace_entity_forms_lib = 'stonehearth.lib.entity_forms.entity_forms_lib',
   ace_equipment_component = 'stonehearth.components.equipment.equipment_component',
   ace_equipment_piece_component = 'stonehearth.components.equipment_piece.equipment_piece_component',
   ace_evolve_component = 'stonehearth.components.evolve.evolve_component',
   ace_expendable_resources_component = 'stonehearth.components.expendable_resources.expendable_resources_component',
   ace_fabricate_chunk_adjacent_action = 'stonehearth.ai.actions.fabrication.fabricate_chunk_adjacent_action',
   ace_farmer = 'stonehearth.jobs.farmer.farmer',
   ace_farmer_field_component = 'stonehearth.components.farmer_field.farmer_field_component',
   ace_farming_call_handler = 'stonehearth.call_handlers.farming_call_handler',
   ace_farming_service = 'stonehearth.services.server.farming.farming_service',
   ace_farming_task_group = 'stonehearth.ai.task_groups.farming_task_group',
   ace_find_best_reachable_entity_by_type = 'stonehearth.ai.actions.find_best_reachable_entity_by_type',
   ace_find_entity_type_in_storage_action = 'stonehearth.ai.actions.find_entity_type_in_storage_action',
   ace_find_equipment_upgrade_action = 'stonehearth.ai.actions.upgrade_equipment.find_equipment_upgrade_action',
   ace_find_healable_target_observer = 'stonehearth.ai.observers.find_healable_target_observer',
   ace_firepit_component = 'stonehearth.components.firepit.firepit_component',
   ace_fixture = 'stonehearth.components.building2.fixture',
   ace_follow_path_action = 'stonehearth.ai.actions.follow_path_action',
   ace_food_available_observer = 'stonehearth.ai.observers.food_available_observer',
   ace_food_preference_script = 'stonehearth.data.traits.food_preference.food_preference_script',
   ace_free_time_observer = 'stonehearth.ai.observers.free_time_observer',
   ace_game_creation_service = 'stonehearth.services.server.game_creation.game_creation_service',
   ace_game_master = 'stonehearth.services.server.game_master.controllers.game_master',
   ace_game_master_lib = 'stonehearth.lib.game_master.game_master_lib',
   ace_game_speed_service = 'stonehearth.services.server.game_speed.game_speed_service',
   ace_geomancer = 'stonehearth.jobs.geomancer.geomancer',
   ace_get_food_trivial_action = 'stonehearth.ai.actions.get_food_trivial_action',
   ace_get_nearby_items_action = 'stonehearth.ai.actions.get_nearby_items_action',
   ace_get_patrol_route_action = 'stonehearth.ai.actions.get_patrol_route_action',
   ace_ghost_form_component = 'stonehearth.components.ghost_form.ghost_form_component',
   ace_growing_component = 'stonehearth.components.growing.growing_component',
   ace_guildmaster_town_bonus = 'stonehearth.data.town_bonuses.guildmaster_town_bonus',
   ace_harvest_crop_adjacent = 'stonehearth.ai.actions.harvest_crop_adjacent',
   ace_harvest_resource_node_adjacent = 'stonehearth.ai.actions.harvest_resource_node_adjacent',
   ace_harvest_renewable_resource_adjacent = 'stonehearth.ai.actions.harvest_renewable_resource_adjacent',
   ace_heal_target = 'stonehearth.entities.consumables.scripts.heal_target',
   ace_health_observer = 'stonehearth.ai.observers.health_observer',
   ace_herbalist = 'stonehearth.jobs.herbalist.herbalist',
   ace_herding_task_group = 'stonehearth.ai.task_groups.herding_task_group',
   ace_hydrology_service = 'stonehearth.services.server.hydrology.hydrology_service',
   ace_incapacitation_component = 'stonehearth.components.incapacitation.incapacitation_component',
   ace_inventory = 'stonehearth.services.server.inventory.inventory',
   ace_inventory_service = 'stonehearth.services.server.inventory.inventory_service',
   ace_inventory_tracker = 'stonehearth.services.server.inventory.inventory_tracker',
   ace_item_quality_component = 'stonehearth.components.item_quality.item_quality_component',
   ace_jacko_script = 'stonehearth.data.gm.campaigns.kitties.arcs.trigger.kitties.encounters.jacko_script',
   ace_job_component = 'stonehearth.components.job.job_component',
   ace_job_info_controller = 'stonehearth.services.server.job.job_info_controller',
   ace_job_service = 'stonehearth.services.server.job.job_service',
   ace_kill_at_zero_health_observer = 'stonehearth.ai.observers.kill_at_zero_health_observer',
   ace_koda_script = 'stonehearth.data.gm.campaigns.kitties.arcs.trigger.kitties.encounters.koda_script',
   ace_ladder_builder = 'stonehearth.services.server.build.ladder_builder',
   ace_ladder_manager = 'stonehearth.services.server.build.ladder_manager',
   ace_lamp_component = 'stonehearth.components.lamp.lamp_component',
   ace_landmark_lib = 'stonehearth.lib.landmark.landmark_lib',
   ace_lease_component = 'stonehearth.components.lease.lease_component',
   ace_loot_drops_component = 'stonehearth.components.loot_drops.loot_drops_component',
   ace_loot_table = 'stonehearth.lib.loot_table.loot_table',
   ace_memorialize_death_action = 'stonehearth.ai.actions.memorialize_death_action',
   ace_mining_service = 'stonehearth.services.server.mining.mining_service',
   ace_mining_zone_component = 'stonehearth.components.mining_zone.mining_zone_component',
   ace_mount_component = 'stonehearth.components.mount.mount_component',
   ace_na_valor_town_bonus = 'northern_alliance.data.town_bonuses.na_valor_town_bonus',
   ace_nearby_item_search = 'stonehearth.services.server.inventory.nearby_item_search',
   ace_ownable_object_component = 'stonehearth.components.ownership.ownable_object_component',
   ace_party_component = 'stonehearth.components.party.party_component',
   ace_patrollable_object = 'stonehearth.services.server.town_patrol.patrollable_object',
   ace_periodic_health_modification = 'stonehearth.data.buffs.scripts.periodic_health_modification',
   ace_personality_component = 'stonehearth.components.personality.personality_component',
   ace_pet_component = 'stonehearth.components.pet.pet_component',
   ace_pet_owner_component = 'stonehearth.components.pet.pet_owner_component',
   ace_pickup_item_from_storage_adjacent_action = 'stonehearth.ai.actions.pickup_item_from_storage_adjacent_action',
   ace_pickup_item_type_from_backpack_action = 'stonehearth.ai.actions.pickup_item_type_from_backpack_action',
   ace_pickup_placed_item_adjacent_action = 'stonehearth.ai.actions.pickup_placed_item_adjacent_action',
   ace_pillage_mission = 'stonehearth.services.server.game_master.controllers.missions.pillage_mission',
   ace_place_carrying_on_structure_adjacent_action = 'stonehearth.ai.actions.place_carrying_on_structure_adjacent_action',
   ace_place_item_call_handler = 'stonehearth.call_handlers.place_item_call_handler',
   ace_plan_job = 'stonehearth.components.building2.plan.jobs.plan_job',
   ace_plant_field_adjacent_action = 'stonehearth.ai.actions.plant_field_adjacent_action',
   ace_player_jobs_controller = 'stonehearth.services.server.job.player_jobs_controller',
   ace_player_market_stall_component = 'stonehearth.components.player_market_stall.player_market_stall_component',
   ace_player_service = 'stonehearth.services.server.player.player_service',
   ace_population_faction = 'stonehearth.services.server.population.population_faction',
   ace_portal_component = 'stonehearth.components.portal.portal_component',
   ace_posture_component = 'stonehearth.components.posture.posture_component',
   ace_presence_component = 'stonehearth.components.presence.presence_component',
   ace_presence_service = 'stonehearth.services.server.presence.presence_service',
   ace_produce_crafted_items = 'stonehearth.ai.actions.produce_crafted_items',
   ace_projectile_component = 'stonehearth.components.projectile.projectile_component',
   ace_promote_unit_to_class_script = 'stonehearth.data.gm.campaigns.amberstone.arcs.trigger.discovery.encounters.30_geomancy.promote_unit_to_class_script',
   ace_put_another_restockable_item_into_backpack_action = 'stonehearth.ai.actions.put_another_restockable_item_into_backpack_action',
   ace_raid_crops_mission = 'stonehearth.services.server.game_master.controllers.missions.raid_crops_mission',
   ace_raid_stockpiles_mission = 'stonehearth.services.server.game_master.controllers.missions.raid_stockpiles_mission',
   ace_raycast_lib = 'stonehearth.ai.lib.raycast_lib',
   ace_reembarkation_encounter = 'stonehearth.services.server.game_master.controllers.encounters.reembarkation_encounter',
   ace_renewable_resource_node_component = 'stonehearth.components.renewable_resource_node.renewable_resource_node_component',
   ace_repair_entity_adjacent_action = 'stonehearth.ai.actions.repair_entity_adjacent_action',
   ace_resource_call_handler = 'stonehearth.call_handlers.resource_call_handler',
   ace_resource_material_tracker = 'stonehearth.services.server.inventory.resource_material_tracker',
   ace_resource_node_component = 'stonehearth.components.resource_node.resource_node_component',
   ace_rest_in_bed_adjacent_action = 'stonehearth.ai.actions.health.rest_in_bed_adjacent_action',
   ace_rest_in_current_bed_action = 'stonehearth.ai.actions.health.rest_in_current_bed_action',
   ace_returning_trader_script = 'stonehearth.services.server.game_master.controllers.script_encounters.returning_trader_script',
   ace_run_in_circles_action = 'stonehearth.ai.actions.pet.run_in_circles_action',
   ace_run_rest_effect_action = 'stonehearth.ai.actions.health.run_rest_effect_action',
   ace_safety_observer = 'stonehearth.ai.observers.safety_observer',
   ace_sandstorm = 'stonehearth.data.weather.sandstorm.sandstorm',
   ace_scenario_modder_services = 'stonehearth.services.server.static_scenario.scenario_modder_services',
   ace_script_encounter = 'stonehearth.services.server.game_master.controllers.encounters.script_encounter',
   ace_seasonal_model_switcher_component = 'stonehearth.components.seasonal_model_switcher.seasonal_model_switcher_component',
   ace_seasons_service = 'stonehearth.services.server.seasons.seasons_service',
   ace_sellable_item_tracker = 'stonehearth.services.server.shop.sellable_item_tracker',
   ace_shared_filters = 'stonehearth.ai.filters.shared_filters',
   ace_shepherd = 'stonehearth.jobs.shepherd.shepherd',
   ace_shepherd_pasture_component = 'stonehearth.components.shepherd_pasture.shepherd_pasture_component',
   ace_shepherded_animal_component = 'stonehearth.components.shepherd_pasture.shepherded_animal_component',
   ace_shepherd_service = 'stonehearth.services.server.shepherd.shepherd_service',
   ace_shop = 'stonehearth.services.server.shop.shop',
   ace_shop_service = 'stonehearth.services.server.shop.shop_service',
   ace_siege_attack_ranged_action = 'stonehearth.ai.actions.combat.siege_attack_ranged_action',
   ace_siege_weapon_component = 'stonehearth.components.siege_weapon.siege_weapon_component',
   ace_simple_caravan_script = 'stonehearth.services.server.game_master.controllers.script_encounters.simple_caravan_script',
   ace_sleep_in_bed_adjacent_action = 'stonehearth.ai.actions.sleeping.sleep_in_bed_adjacent_action',
   ace_sleep_in_current_bed_action = 'stonehearth.ai.actions.sleeping.sleep_in_current_bed_action',
   ace_sleepiness_observer = 'stonehearth.ai.observers.sleepiness_observer',
   ace_spawn_enemies_mission = 'stonehearth.services.server.game_master.controllers.missions.spawn_enemies_mission',
   ace_stacks_component = 'stonehearth.components.stacks.stacks_component',
   ace_stockpile_component = 'stonehearth.components.stockpile.stockpile_component',
   ace_storage_component = 'stonehearth.components.storage.storage_component',
   ace_structure = 'stonehearth.components.building2.structure',
   ace_swimming_service = 'stonehearth.services.server.swimming.swimming_service',
   ace_task_tracker_component = 'stonehearth.components.task_tracker.task_tracker_component',
   ace_teleportation_component = 'stonehearth.components.teleportation.teleportation_component',
   ace_tentacle_snared_debuff = 'stonehearth.data.buffs.tentacle_snared.tentacle_snared_debuff',
   ace_terrain = 'radiant.modules.terrain',
   ace_terrain_patch_component = 'stonehearth.components.terrain_patch.terrain_patch_component',
   ace_terrain_service = 'stonehearth.services.server.terrain.terrain_service',
   ace_thunderstorm = 'stonehearth.data.weather.thunderstorm.thunderstorm',
   ace_town = 'stonehearth.services.server.town.town',
   ace_town_call_handler = 'stonehearth.call_handlers.town_call_handler',
   ace_town_patrol_service = 'stonehearth.services.server.town_patrol.town_patrol_service',
   ace_town_service = 'stonehearth.services.server.town.town_service',
   ace_town_upgrade_encounter = 'stonehearth.services.server.game_master.controllers.encounters.town_upgrade_encounter',
   ace_trait = 'stonehearth.components.traits.trait',
   ace_trapper = 'stonehearth.jobs.trapper.trapper',
   ace_trapping_grounds_component = 'stonehearth.components.trapping.trapping_grounds_component',
   ace_trapping_service = 'stonehearth.services.server.trapping.trapping_service',
   ace_traveler_component = 'stonehearth.components.traveler.traveler_component',
   ace_trivial_death_component = 'stonehearth.components.incapacitation.trivial_death_component',
   ace_unit_info_component = 'stonehearth.components.unit_info.unit_info_component',
   ace_unit_wait_at_location_action = 'stonehearth.ai.actions.unit_control.unit_wait_at_location_action',
   ace_unlock_crop = 'stonehearth.entities.consumables.scripts.unlock_crop',
   ace_unlock_recipe_encounter = 'stonehearth.services.server.game_master.controllers.encounters.unlock_recipe_encounter',
   ace_useable_item_tracker = 'stonehearth.services.server.inventory.useable_item_tracker',
   ace_util = 'radiant.lib.util',
   ace_valor_town_bonus = 'stonehearth.data.town_bonuses.valor_town_bonus',
   ace_wander_mission = 'stonehearth.services.server.game_master.controllers.missions.wander_mission',
   ace_wait_for_closest_storage_space = 'stonehearth.ai.actions.wait_for_closest_storage_space',
   ace_wait_for_net_worth_encounter = 'stonehearth.services.server.game_master.controllers.encounters.wait_for_net_worth_encounter',
   ace_water_component = 'stonehearth.components.water.water_component',
   ace_waterfall_component = 'stonehearth.components.waterfall.waterfall_component',
   ace_weather_service = 'stonehearth.services.server.weather.weather_service',
   ace_weather_state = 'stonehearth.services.server.weather.weather_state',
   ace_workshop_component = 'stonehearth.components.workshop.workshop_component',
   ace_world_generation_service = 'stonehearth.services.server.world_generation.world_generation_service',
}

local function monkey_patching()
   for from, into in pairs(monkey_patches) do
      local monkey_see = require('monkey_patches.' .. from)
      local monkey_do = radiant.mods.require(into)
      if monkey_see and monkey_do then
         radiant.log.write_('stonehearth_ace', 0, 'ACE server monkey-patching sources \'' .. from .. '\' => \'' .. into .. '\'')
         --radiant.log.write_('stonehearth_ace', 0, 'ACE server monkey-patching data \'' .. tostring(monkey_see) .. '\' => \'' .. tostring(monkey_do) .. '\'')
         if monkey_see.ACE_USE_MERGE_INTO_TABLE then
            -- use merge_into_table to also mixin other values, not just functions
            radiant.util.merge_into_table(monkey_do, monkey_see)
         else
            radiant.mixin(monkey_do, monkey_see)
         end
      else
         radiant.log.write_('stonehearth_ace', 0, 'ACE server ***INVALID*** monkey-patching sources \'' .. from .. '\' => \'' .. into .. '\'')
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
   radiant.log.write_('stonehearth_ace', 0, 'ACE server service initialized: %s', name)
end

function stonehearth_ace:_on_init()
   stonehearth_ace._sv = stonehearth_ace.__saved_variables:get_data()

   self:_run_scripts('pre_ace_services')

   for _, name in ipairs(service_creation_order) do
      create_service(name)
   end

   radiant.events.trigger(radiant, 'stonehearth_ace:server:init')
   radiant.log.write_('stonehearth_ace', 0, 'ACE server initialized')
end

function stonehearth_ace:_on_required_loaded()
   monkey_patching()

   self:_run_scripts('post_monkey_patching')
   
   radiant.events.trigger(radiant, 'stonehearth_ace:server:required_loaded')
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

function stonehearth_ace:load_version_info()
   self.version_info = radiant.resources.load_json('stonehearth_ace/version.json') or {}
end

stonehearth_ace:load_version_info()
radiant.events.listen(stonehearth_ace, 'radiant:init', stonehearth_ace, stonehearth_ace._on_init)
radiant.events.listen(radiant, 'radiant:required_loaded', stonehearth_ace, stonehearth_ace._on_required_loaded)

print("Mod List:")
print(radiant.resources.get_mod_list())

return stonehearth_ace
