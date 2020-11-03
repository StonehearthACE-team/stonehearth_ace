local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local Material = require 'components.material.material'
local log = radiant.log.create_logger('catalog')

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
            result = catalog_lib._update_catalog_data(catalog, full_alias, json)
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
                  _all_alternate_uris[iconic_uri] = alternate_iconic_uris
                  alternate_iconic_uris[iconic_uri] = true
                  iconic_data.alternate_uris = alternate_iconic_uris
               end
            end
         end
      end
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
function catalog_lib._update_catalog_data(catalog, full_alias, json)
   return catalog_lib._add_catalog_description(catalog, full_alias, json, DEFAULT_CATALOG_DATA)
end

function catalog_lib._add_catalog_description(catalog, full_alias, json, base_data)
   if catalog[full_alias] ~= nil then
      return
   end

   local catalog_data = radiant.shallow_copy(base_data)

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
         if net_worth and net_worth.shop_info then
            catalog_data.shopkeeper_level = net_worth.shop_info.shopkeeper_level or -1
            if net_worth.shop_info.buyable then
               result.buyable = true
            end
         end
      end

      local catalog = entity_data['stonehearth:catalog']
      if catalog ~= nil then
         if catalog.display_name ~= nil then
            catalog_data.display_name = catalog.display_name
         end
         if catalog.description ~= nil then
            catalog_data.description = catalog.description
         end
         if catalog.icon ~= nil then
            catalog_data.icon = catalog.icon
         end
         if catalog.category ~= nil then
            catalog_data.category = catalog.category
         end
         if catalog.is_item ~= nil then
            catalog_data.is_item = catalog.is_item
         end
         if catalog.material_tags ~= nil then
            catalog_data.materials = catalog.material_tags
         end
         if catalog.player_id ~= nil then
            catalog_data.player_id = catalog.player_id
         end
         if catalog.subject_override ~= nil then
            catalog_data.subject_override = catalog.subject_override
         end
         if catalog.alternate_builder_uri ~= nil then
            catalog_data.alternate_uris = catalog_lib.set_alternate_uris(catalog, catalog.alternate_builder_uri, full_alias)
         else
            -- this is the original; the alternates already have their catalog_data.alternate_uris assigned
            catalog_data.alternate_uris = catalog_lib.get_alternate_uris(full_alias)
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
            catalog_lib._add_catalog_description(catalog, iconic_path, iconic_json, catalog_data)
            catalog_data.iconic_uri = iconic_path
         end

         local ghost_path = entity_forms.ghost_form
         if ghost_path then
            local ghost_json = catalog_lib._load_json(ghost_path)
            catalog_lib._add_catalog_description(catalog, ghost_path, ghost_json, catalog_data)
         end
      end
      
      if json.components['stonehearth:equipment_piece'] then
         catalog_data.equipment_required_level = json.components['stonehearth:equipment_piece'].required_job_level
         catalog_data.equipment_roles = json.components['stonehearth:equipment_piece'].roles
         catalog_data.equipment_types = catalog_lib.get_equipment_types(json.components['stonehearth:equipment_piece'])
         catalog_data.injected_buffs = catalog_lib.get_buffs(json.components['stonehearth:equipment_piece'].injected_buffs)
      end
      
      catalog_data.max_stacks = json.components['stonehearth:stacks'] and json.components['stonehearth:stacks'].max_stacks

      if json.components['stonehearth:storage'] then
         catalog_data.is_storage = true
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
      if weapon_data and weapon_data.base_damage then
         catalog_data.combat_damage = weapon_data.base_damage
      end

      local armor_data = entity_data['stonehearth:combat:armor_data']
      if armor_data and armor_data.base_damage_reduction then
         catalog_data.combat_armor = armor_data.base_damage_reduction
      end

      if entity_data['stonehearth:buffs'] and entity_data['stonehearth:buffs'].inflictable_debuffs then
         catalog_data.inflictable_debuffs = catalog_lib.get_buffs(entity_data['stonehearth:buffs'].inflictable_debuffs)
      end

      local stacks = catalog_data.max_stacks or 1

      if entity_data['stonehearth:food_container'] and entity_data['stonehearth:food_container'].food then
         local stacks_per_serving = entity_data['stonehearth:food_container'].stacks_per_serving or 1
         catalog_data.food_servings = math.ceil(stacks / math.max(1, stacks_per_serving))
         local food_json = radiant.resources.load_json(entity_data['stonehearth:food_container'].food)
         if food_json and food_json.entity_data and food_json.entity_data['stonehearth:food'] then
            local food = food_json.entity_data['stonehearth:food']
            if food.applied_buffs then
               catalog_data.consumable_buffs = catalog_lib.get_buffs(food.applied_buffs)
            end
            local satisfaction = food['stonehearth:sitting_on_chair'] or food.default
            catalog_data.food_satisfaction = satisfaction and satisfaction.satisfaction
            catalog_data.food_quality = food.quality
         end
      end
		
      if entity_data['stonehearth_ace:drink_container'] and entity_data['stonehearth_ace:drink_container'].drink then
         local stacks_per_serving = entity_data['stonehearth_ace:drink_container'].stacks_per_serving or 1
         catalog_data.drink_servings = math.ceil(stacks / math.max(1, stacks_per_serving))
         local drink_json = radiant.resources.load_json(entity_data['stonehearth_ace:drink_container'].drink)
         if drink_json and drink_json.entity_data and drink_json.entity_data['stonehearth_ace:drink'] then
            local drink = drink_json.entity_data['stonehearth_ace:drink']
            if drink.applied_buffs then
               catalog_data.consumable_buffs = catalog_lib.get_buffs(drink.applied_buffs)
            end
            local satisfaction = drink['stonehearth:sitting_on_chair'] or drink.default
            catalog_data.drink_satisfaction = satisfaction and satisfaction.satisfaction
            catalog_data.drink_quality = drink.quality
         end
      end

      if entity_data['stonehearth_ace:buildable_data'] then
         catalog_data.is_buildable = true
      end

      if entity_data['stonehearth_ace:fence_data'] then
         catalog_data.fence_length = entity_data['stonehearth_ace:fence_data'].length
      end
   end

   catalog[full_alias] = catalog_data
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

return catalog_lib
