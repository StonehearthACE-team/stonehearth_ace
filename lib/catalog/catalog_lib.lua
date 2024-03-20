local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local Material = require 'components.material.material'
local log = radiant.log.create_logger('catalog')
local log_mods = radiant.resources.load_json('stonehearth_ace/lib/catalog/catalog_logging.json').mods

local catalog_lib = {}
local _all_alternate_uris = {}

local DEFAULT_CATALOG_DATA = {
   display_name = '',
   description = '',
   player_id = nil,
   icon = nil,
   net_worth = nil,
   sell_cost = nil,
   shopkeeper_level = nil,
   category = nil,
   materials = nil,
   is_item = nil,
   root_entity_uri = nil,
   iconic_uri = nil
}

local TRACK_MATERIALS = false
local _total_materials = 0
local _total_combinations = 0
local _max_materials = 0
local _total_entities = 0

function catalog_lib.load_catalog(catalog, added_cb)
   local mods = radiant.resources.get_mod_list()

   local entity_scripts
   local type_scripts
   local scripts = radiant.resources.load_json('stonehearth_ace/scripts/catalog_scripts.json')
   if scripts then
      for script, run in pairs(scripts.entity_scripts or {}) do
         if run then
            local s = require(script)
            if s and type(s.update_catalog_data) == 'function' then
               if not entity_scripts then
                  entity_scripts = {}
               end
               table.insert(entity_scripts, s.update_catalog_data)
            end
         end
      end
      for script, run in pairs(scripts.type_scripts or {}) do
         if run then
            local s = require(script)
            if s and type(s.update_catalog_data) == 'function' then
               if not type_scripts then
                  type_scripts = {}
               end
               table.insert(type_scripts, s.update_catalog_data)
            end
         end
      end
   end

   _all_alternate_uris = {}

   -- for each mod
   for i, mod in ipairs(mods) do
      local manifest = radiant.resources.load_manifest(mod)
      -- for each alias
      local aliases = {}
      if manifest.aliases then
         radiant.util.merge_into_table(aliases, manifest.aliases)
      end
      if manifest.deprecated_aliases then
         radiant.util.merge_into_table(aliases, manifest.deprecated_aliases)
      end
      -- can be faster if give the entities aliases their own node
      for alias in pairs(aliases) do
         local full_alias = string.format('%s:%s', mod, alias)
         local json = catalog_lib._load_json(full_alias)
         local json_type = json and json.type
         if json_type == 'entity' then
            -- this does the base-game catalog-building (with ACE additions)
            -- the base game only cares about entities, and the added_cb can't be modified without overriding the catalog service files
            -- so just assume it only applies to base game things
            local result = catalog_lib._update_catalog_data(catalog, full_alias, json, mod)
            if entity_scripts then
               for _, script in ipairs(entity_scripts) do
                  script(catalog, full_alias, json, DEFAULT_CATALOG_DATA)
               end
            end
            if added_cb then
               added_cb(full_alias, result)
            end
         end

         if type_scripts then
            for _, script in ipairs(type_scripts) do
               script(catalog, full_alias, json, json_type, DEFAULT_CATALOG_DATA)
            end
         end
      end
   end

   -- post-processing
   -- go through the alternate uris and make sure their iconics are also associated with one another
   local checked = {}
   for _, alternates in pairs(_all_alternate_uris) do
      if not checked[alternates] then
         checked[alternates] = true

         local alternate_iconic_uris = {}
         for uri, _ in pairs(alternates) do
            local catalog_data = catalog[uri]
            if catalog_data then
               catalog_data.alternate_iconic_uris = alternate_iconic_uris
               local iconic_uri = catalog_data.iconic_uri
               local iconic_data = iconic_uri and catalog[iconic_uri]
               if iconic_data then
                  checked[alternate_iconic_uris] = true
                  _all_alternate_uris[iconic_uri] = alternate_iconic_uris
                  alternate_iconic_uris[iconic_uri] = true
                  iconic_data.alternate_uris = alternate_iconic_uris
               end
            end
         end
      end
   end

   if TRACK_MATERIALS then
      log:debug('finished loading catalog: total entities = %s, max materials = %s, avg materials = %s, total (avg) combinations = %s (%s)',
            _total_entities, _max_materials, _total_materials / _total_entities, _total_combinations, _total_combinations / _total_entities)
   end

   return catalog
end

function catalog_lib._is_deprecated(alias)
   local alias_parts = alias:split(':', 1)
   if #alias_parts < 2 then
      return false
   end
   local mod = alias_parts[1]
   local local_alias = alias_parts[2]
   local manifest = radiant.resources.load_manifest(mod)
   return manifest.deprecated_aliases ~= nil and manifest.deprecated_aliases[local_alias] ~= nil
end

function catalog_lib._load_json(full_alias)
   local path = radiant.resources.convert_to_canonical_path(full_alias)

   -- needs to be fast
   if not path or string.sub(path, -5) ~= '.json' then
      return nil
   end

   local json = radiant.resources.load_json(path)
   return json
end

-- Note ghost forms and some iconics are not marked as entities in the manifest but probably should be
function catalog_lib._load_entity_json(full_alias)
   local json = catalog_lib._load_json(full_alias)
   local alias_type = json and json.type

   if alias_type == 'entity' then
      return json
   else
      return nil
   end
end

-- Add catalog description for this alias and insert in buyable items if applicable
function catalog_lib._update_catalog_data(catalog, full_alias, json, mod)
   return catalog_lib._add_catalog_description(catalog, full_alias, json, DEFAULT_CATALOG_DATA, mod)
end

function catalog_lib._add_catalog_description(catalog, full_alias, json, base_data, mod)
   if catalog[full_alias] ~= nil then
      return
   end

   local catalog_data = radiant.shallow_copy(base_data)
   catalog[full_alias] = catalog_data

   local result = {
      buyable = false,
      likeable = false
   }

   local entity_data = json.entity_data

   if entity_data ~= nil then
      local net_worth = entity_data['stonehearth:net_worth']
      if net_worth ~= nil then
         catalog_data.net_worth = net_worth.value_in_gold or 0
         catalog_data.sell_cost = net_worth.value_in_gold or 0
         catalog_data.sell_cost = math.ceil(catalog_data.sell_cost * stonehearth.constants.shop.SALE_MULTIPLIER)
         if net_worth.rarity then
            catalog_data.rarity = net_worth.rarity
         end
         if net_worth and net_worth.shop_info and net_worth.value_in_gold then
            catalog_data.shopkeeper_level = net_worth.shop_info.shopkeeper_level or -1
            if net_worth.shop_info.buyable then
               result.buyable = true
            end
            result.specific_buyable = true
            catalog_data.sellable_only_if_wanted = net_worth.shop_info.sellable_only_if_wanted
         end
      end

      local catalog_entity_data = entity_data['stonehearth:catalog']
      if catalog_entity_data ~= nil then
         if catalog_entity_data.display_name ~= nil then
            catalog_data.display_name = catalog_entity_data.display_name
         end
         if catalog_entity_data.description ~= nil then
            catalog_data.description = catalog_entity_data.description
         end
         if catalog_entity_data.icon ~= nil then
            catalog_data.icon = catalog_entity_data.icon
         end
         if catalog_entity_data.category ~= nil then
            catalog_data.category = catalog_entity_data.category
         end
         if catalog_entity_data.is_item ~= nil then
            catalog_data.is_item = catalog_entity_data.is_item
         end
         if catalog_entity_data.material_tags ~= nil then
            catalog_data.materials = catalog_entity_data.material_tags
         end
         if catalog_entity_data.player_id ~= nil then
            catalog_data.player_id = catalog_entity_data.player_id
         end
         if catalog_entity_data.subject_override ~= nil then
            catalog_data.subject_override = catalog_entity_data.subject_override
         end
         if catalog_entity_data.alternate_builder_uri ~= nil then
            catalog_data.alternate_uris = catalog_lib.set_alternate_uris(catalog, catalog_entity_data.alternate_builder_uri, full_alias)
         else
            local alternates = catalog_lib.get_alternate_uris(full_alias)
            if alternates then
               -- this is the original; the alternates already have their catalog_data.alternate_uris assigned
               catalog_data.alternate_uris = alternates
            end
         end
      end
   end

   if base_data.deprecated or catalog_lib._is_deprecated(full_alias) then
      catalog_data.deprecated = true
   end

   if json.components then
      if json.components['stonehearth:material'] then
         catalog_data.materials = json.components['stonehearth:material'].tags or ''
      end

      local entity_forms = json.components['stonehearth:entity_forms']
      if entity_forms then
         catalog_data.root_entity_uri = full_alias

         local iconic_path = entity_forms.iconic_form
         if iconic_path then
            local iconic_json = catalog_lib._load_json(iconic_path)
            if iconic_json then
               catalog_lib._add_catalog_description(catalog, iconic_path, iconic_json, catalog_data, mod)
               catalog_data.iconic_uri = iconic_path
               -- if it has an iconic form, the root form shouldn't be considered an item, and the iconic form should be
               catalog[iconic_path].is_item = true
               catalog_data.is_item = false  -- unless this causes problems with other game systems that expect root entities to be items?
            else
               log:error('%s has invalid iconic path specified: %s', full_alias, tostring(iconic_path))
            end
         end

         local ghost_path = entity_forms.ghost_form
         if ghost_path then
            local ghost_json = catalog_lib._load_json(ghost_path)
            if ghost_json then
               catalog_lib._add_catalog_description(catalog, ghost_path, ghost_json, catalog_data, mod)
               -- make sure the ghost isn't considered an item
               catalog[ghost_path].is_item = false
            else
               log:error('%s has invalid ghost path specified: %s', full_alias, tostring(iconic_path))
            end
         end

         catalog_data.is_placeable = entity_forms.placeable_on_ground or entity_forms.placeable_on_walls
      end

      if json.components['stonehearth:equipment_piece'] then
         catalog_data.equipment_required_level = json.components['stonehearth:equipment_piece'].required_job_level
         catalog_data.equipment_roles = json.components['stonehearth:equipment_piece'].roles
         catalog_data.equipment_types = catalog_lib.get_equipment_types(json.components['stonehearth:equipment_piece'])
         catalog_data.equipment_ilevel = json.components['stonehearth:equipment_piece'].ilevel
         catalog_data.injected_buffs = catalog_lib.get_buffs(json.components['stonehearth:equipment_piece'].injected_buffs)
      end

      catalog_data.max_stacks = json.components['stonehearth:stacks'] and json.components['stonehearth:stacks'].max_stacks

      if json.components['stonehearth:storage'] and json.components['stonehearth:storage'].is_public ~= false and
            not json.components['stonehearth:storage'].is_hidden then
         catalog_data.is_storage = true
         local capacity = json.components['stonehearth:storage'].capacity
         if json.components['stonehearth_ace:consumer'] then
            catalog_data.fuel_capacity = capacity
         else
            catalog_data.storage_capacity = capacity
         end
      end

      -- TODO: also check ghost for collision / landmark dimensions
      if json.components['region_collision_shape'] and json.components['region_collision_shape'].region then
         local region = Region3()
         region:load(json.components['region_collision_shape'].region)
         catalog_data.collision_size = region:get_bounds():get_size()
      end

      if json.components['sensor_list'] and json.components['sensor_list'].sensors and json.components['sensor_list'].sensors.warmth then
         catalog_data.warmth_radius = json.components['sensor_list'].sensors.warmth.radius
      end

      -- buffs this entity has (e.g., aura buffs)
      if json.components['stonehearth:buffs'] then
         catalog_data.buffs = catalog_lib.get_buffs(json.components['stonehearth:buffs'].buffs)
      end

      if json.components['stonehearth:lamp'] and json.components['stonehearth:lamp'].buff_source then
         local buffs = catalog_lib.get_buffs({json.components['stonehearth:lamp'].buff or 'stonehearth_ace:buffs:weather:warmth_source'})
         if catalog_data.buffs then
            for _, buff in ipairs(buffs) do
               table.insert(catalog_data.buffs, buff)
            end
         else
            catalog_data.buffs = buffs
         end
      end

      if json.components['stonehearth:firepit'] and json.components['stonehearth:firepit'].buff_source then
         local buffs = catalog_lib.get_buffs({json.components['stonehearth:firepit'].buff or 'stonehearth_ace:buffs:weather:warmth_source'})
         if catalog_data.buffs then
            for _, buff in ipairs(buffs) do
               table.insert(catalog_data.buffs, buff)
            end
         else
            catalog_data.buffs = buffs
         end
      end

      if json.components['stonehearth:attributes'] then
         if json.components['stonehearth:attributes'].max_health then
            catalog_data.max_health = json.components['stonehearth:attributes'].max_health.value
         end
         if json.components['stonehearth:attributes'].menace and json.components['stonehearth:siege_weapon'] then
            catalog_data.menace = json.components['stonehearth:attributes'].menace.value
         end
      end
   end

   if entity_data ~= nil then
      local appeal = entity_data['stonehearth:appeal']
      if appeal then
         catalog_data.appeal = appeal['appeal']
         if json.components then
            local entity_forms = json.components['stonehearth:entity_forms']
            if entity_forms then
               result.likeable = (catalog_data.appeal > 0 and
                                  not catalog_data.deprecated and
                                  (entity_forms.placeable_on_ground or entity_forms.placeable_on_walls))
            end
         end
      end

      local reembarkation = entity_data['stonehearth:reembarkation']
      if reembarkation and reembarkation.reembark_version then
         catalog_data.reembark_version = reembarkation.reembark_version
         catalog_data.reembark_max_count = reembarkation.reembark_max_count
      end

      local workshop = entity_data['stonehearth:workshop']
      if workshop and workshop.equivalents then
         catalog_data.workshop_equivalents = workshop.equivalents
      end

      local weapon_data = entity_data['stonehearth:combat:weapon_data']
      if weapon_data then
         catalog_data.combat_damage = weapon_data.range and weapon_data.base_ranged_damage or weapon_data.base_damage
         catalog_data.combat_range = weapon_data.range or weapon_data.reach
      end

      local armor_data = entity_data['stonehearth:combat:armor_data']
      if armor_data and armor_data.base_damage_reduction then
         catalog_data.combat_armor = armor_data.base_damage_reduction
      end

      if entity_data['stonehearth:buffs'] and entity_data['stonehearth:buffs'].inflictable_debuffs then
         catalog_data.inflictable_debuffs = catalog_lib.get_buffs(entity_data['stonehearth:buffs'].inflictable_debuffs)
      end

      local stacks = catalog_data.max_stacks or 1

      local consumable_data = entity_data['stonehearth:consumable']
      if consumable_data then
         if consumable_data.script == 'stonehearth:consumables:scripts:buff_town' then
            local quality_1 = entity_data['stonehearth:consumable'].consumable_qualities and entity_data['stonehearth:consumable'].consumable_qualities[1]
            local buffs = quality_1 and quality_1.buff
            if not buffs then
               buffs = entity_data['stonehearth:consumable'].buff
            end
            if type(buffs) == 'string' then
               buffs = { buffs }
            end

            if buffs and #buffs > 0 then
               catalog_data.consumable_effects = catalog_lib.get_buffs(buffs)
               if catalog_data.consumable_effects then
                  local after_effects = {}
                  for _, buff_data in ipairs(catalog_data.consumable_effects) do
                     if buff_data.cooldown_buff then
                        table.insert(after_effects, buff_data.cooldown_buff)
                     end
                  end

                  if #after_effects > 0 then
                     catalog_data.consumable_after_effects = catalog_lib.get_buffs(after_effects)
                  end
               end
            end
         elseif consumable_data.script == 'stonehearth:consumables:scripts:unlock_crop' then
            catalog_data.unlocks_crop = consumable_data.crop
         end
      end

      if entity_data['stonehearth:food_container'] then
         local food_uri = entity_data['stonehearth:food_container'].food
         local food_json = food_uri and radiant.resources.load_json(food_uri)
         if food_json and food_json.entity_data and food_json.entity_data['stonehearth:food'] then
            local stacks_per_serving = entity_data['stonehearth:food_container'].stacks_per_serving or 1
            catalog_data.food_servings = math.ceil(stacks / math.max(1, stacks_per_serving))

            local food = food_json.entity_data['stonehearth:food']
            if food.applied_buffs then
               catalog_data.consumable_buffs = catalog_lib.get_buffs(food.applied_buffs)
            end
            local satisfaction = food.default   --food['stonehearth:sitting_on_chair'] or 
            catalog_data.food_satisfaction = satisfaction and satisfaction.satisfaction
            catalog_data.food_quality = food.quality
            if catalog_data.materials then
               local food_materials = catalog_lib._get_material_table(catalog_data.materials)
               catalog_data.food_attributes = {
                  is_warming = food_materials.warming,
                  is_refreshing = food_materials.refreshing,
                  is_breakfast_time = food_materials.breakfast_time,
                  is_lunch_time = food_materials.lunch_time,
                  is_dinner_time = food_materials.dinner_time,
                  is_night_time = food_materials.night_time,
               }
            else
               catalog_data.food_attributes = {}
            end
         else
            log:error('%s food from container %s isn\'t real food!', tostring(food_uri), full_alias)
         end
      elseif entity_data['stonehearth_ace:pet_food_container'] then
         local food_uri = entity_data['stonehearth_ace:pet_food_container'].food
         local food_json = food_uri and radiant.resources.load_json(food_uri)
         if food_json and food_json.entity_data and food_json.entity_data['stonehearth:food'] then
            catalog_data.is_pet_food = true
         end
      elseif entity_data['stonehearth_ace:animal_feed_container'] then
         local food_uri = entity_data['stonehearth_ace:animal_feed_container'].ground_form
         local food_json = food_uri and radiant.resources.load_json(food_uri)
         if food_json and food_json.entity_data and food_json.entity_data['stonehearth:animal_feed'] then
            local feed_stacks = food_json.components['stonehearth:stacks'] and food_json.components['stonehearth:stacks'].max_stacks or 1
            catalog_data.is_animal_feed = true
            catalog_data.food_servings = feed_stacks
         end
      end

      if entity_data['stonehearth_ace:drink_container'] then
         local drink_uri, sub_levels = catalog_lib._get_drink_uri(entity_data['stonehearth_ace:drink_container'])
         local drink_json = drink_uri and radiant.resources.load_json(drink_uri)
         if drink_json and drink_json.entity_data and drink_json.entity_data['stonehearth_ace:drink'] then
            local stacks_per_serving = entity_data['stonehearth_ace:drink_container'].stacks_per_serving or 1
            catalog_data.drink_servings = math.ceil(stacks / math.max(1, stacks_per_serving))

            local drink = drink_json.entity_data['stonehearth_ace:drink']
            if drink.applied_buffs then
               catalog_data.consumable_buffs = catalog_lib.get_buffs(drink.applied_buffs)
            end
            local satisfaction = drink.default  --drink['stonehearth:sitting_on_chair'] or 
            catalog_data.drink_satisfaction = satisfaction and satisfaction.satisfaction
            catalog_data.drink_quality = drink.quality - 0.1 * sub_levels

            -- make sure we're on the server before trying to check catalog materials
            -- this only needs to happen on the server anyway; it's for eating/drinking ai
            if catalog_data.materials then
               local drink_materials = catalog_lib._get_material_table(catalog_data.materials)
               catalog_data.drink_attributes = {
                  is_warming = drink_materials.warming,
                  is_refreshing = drink_materials.refreshing,
                  is_morning_time = drink_materials.morning_time,
                  is_afternoon_time = drink_materials.afternoon_time,
                  is_night_time = drink_materials.night_time,
               }
            else
               catalog_data.drink_attributes = {}
            end
         else
            log:error('%s drink from container %s isn\'t a real drink!', tostring(drink_uri), full_alias)
         end
      end

      if entity_data['stonehearth_ace:buildable_data'] then
         catalog_data.is_buildable = true
      end

      if entity_data['stonehearth_ace:fence_data'] then
         catalog_data.fence_length = entity_data['stonehearth_ace:fence_data'].length
      end

      if entity_data['stonehearth:species'] then
         catalog_data.species_name = entity_data['stonehearth:species'].display_name
      end

      if entity_data['stonehearth_ace:fuel'] then
         catalog_data.fuel_amount = entity_data['stonehearth_ace:fuel'].fuel_amount
      end
   end

   if not catalog_data.materials then
      -- assume everything in the base game (and ACE) that should have materials does
      if log_mods[mod] ~= false then
         log:error('%s has no materials', full_alias)
      end
   elseif TRACK_MATERIALS then
      local mats = type(catalog_data.materials) == 'string' and radiant.util.split_string(catalog_data.materials) or catalog_data.materials
      _total_entities = _total_entities + 1
      _total_materials = _total_materials + #mats
      _total_combinations = _total_combinations + 2 ^ #mats
      _max_materials = math.max(_max_materials, #mats)

      if #mats > 7 then
         --log:debug('high materials (%s) entity %s : %s', #mats, full_alias, table.concat(mats, ' '))
      end
   end

   result.catalog_data = catalog_data
   return result
end

function catalog_lib.get_alternate_uris(uri)
   return _all_alternate_uris[uri]
end

function catalog_lib.set_alternate_uris(catalog, uri1, uri2)
   local alternates
   local alternates1, alternates2 = _all_alternate_uris[uri1], _all_alternate_uris[uri2]
   if alternates1 and alternates2 then
      -- go through each in the alternates2 list and, if their catalog data exists, set them to the first one
      for uri, _ in pairs(alternates2) do
         catalog_lib._set_alternate_uris(catalog, uri, alternates1)
      end
      return alternates1
   else
      alternates = alternates1 or alternates2
      if not alternates then
         alternates = {}
      end
   end

   catalog_lib._set_alternate_uris(catalog, uri1, alternates)
   catalog_lib._set_alternate_uris(catalog, uri2, alternates)

   return alternates
end

function catalog_lib._set_alternate_uris(catalog, uri, alternates)
   alternates[uri] = true
   _all_alternate_uris[uri] = alternates
   local catalog_data = catalog[uri]
   if catalog_data then
      catalog_data.alternate_uris = alternates
   end
end

function catalog_lib.get_equipment_types(json)
   local equipment_types = {}
   local types = json.equipment_types or catalog_lib._get_default_equipment_types(json)
   for _, type in ipairs(types) do
      equipment_types[type] = true
   end
   return equipment_types
end

-- other mods that want to add in additional default types can easily patch this to first call this version of the function
-- and then additionally insert their other types into the resulting table before returning it
function catalog_lib._get_default_equipment_types(json)
   -- if equipment types aren't specified, evaluate other properties to see what they should probably be
   local types = {}
   if json.slot == 'mainhand' then
      if json.additional_equipment and json.additional_equipment['stonehearth:armor:offhand_placeholder'] then
         table.insert(types, 'twohanded')
      else
         table.insert(types, 'mainhand')
      end
   else
      table.insert(types, json.slot)
   end

   return types
end

function catalog_lib.get_buffs(buff_data)
   local buffs = {}
   local buff_lookup = {}
   if buff_data then
      for buff, data in pairs(buff_data) do
         local uri = data
         local stacks = 1
         if type(data) == 'table' then
            uri = data.uri
            stacks = data.stacks or 1
         elseif type(data) == 'boolean' then
            uri = buff
         end

         local json = radiant.resources.load_json(uri)
         if json then
            local struct = buff_lookup[uri]
            if struct then
               struct.stacks = struct.stacks + stacks
            else
               struct = {
                  uri = uri,
                  axis = json.axis,
                  display_name = json.display_name,
                  description = json.description,
                  icon = json.icon,
                  stacks = stacks,
                  cooldown_buff = json.cooldown_buff,
                  invisible_to_player = json.invisible_to_player,
                  invisible_on_crafting = json.invisible_on_crafting
               }
               buff_lookup[uri] = struct
               table.insert(buffs, struct)
            end
         end
      end
   end
   return buffs
end

function catalog_lib._get_material_table(materials)
   local mats = {}
   if radiant.util.is_string(materials) then
      materials = radiant.util.split_string(materials)
   end
   for _, mat in ipairs(materials) do
      mats[mat] = true
   end
   return mats
end

function catalog_lib._get_drink_uri(drink_container)
   local drink_uri
   local sub_levels = 0

   repeat
      if drink_container then
         local subcontainer = drink_container.subcontainer
         if subcontainer then
            local json = radiant.resources.load_json(subcontainer)
            drink_container = json and json.entity_data and json.entity_data['stonehearth_ace:drink_container']
            sub_levels = sub_levels + 1
         else
            drink_uri = drink_container.drink
         end
      end
   until not drink_container or drink_uri

   return drink_uri, sub_levels
end

return catalog_lib
