local catalog_lib = require 'stonehearth.lib.catalog.catalog_lib'
local log = radiant.log.create_logger('ace_catalog_lib')
local ace_catalog_lib = {}

ace_catalog_lib._ace_old__add_catalog_description = catalog_lib._add_catalog_description
function ace_catalog_lib._add_catalog_description(catalog, full_alias, json, base_data)
   local result = ace_catalog_lib._ace_old__add_catalog_description(catalog, full_alias, json, base_data)

   if result and result.catalog_data then
      ace_catalog_lib._update_catalog_data(result.catalog_data)
   end

   return result
end

-- if the catalog has already been loaded without accounting for our changes (likely), update all entries
function ace_catalog_lib.update_catalog(catalog)
   for uri, catalog_data in pairs(catalog) do
      ace_catalog_lib._update_catalog_data(catalog_data, uri)
   end
end

function ace_catalog_lib._update_catalog_data(catalog_data, uri, json)
   json = json or radiant.resources.load_json(uri)
   if json and json.components and json.components['stonehearth:equipment_piece'] then
      catalog_data.equipment_types = ace_catalog_lib.get_equipment_types(json.components['stonehearth:equipment_piece'])
      catalog_data.injected_buffs = ace_catalog_lib.get_buffs(json.components['stonehearth:equipment_piece'].injected_buffs)
   end

   if json and json.entity_data and json.entity_data['stonehearth:buffs'] and json.entity_data['stonehearth:buffs'].inflictable_debuffs then
      catalog_data.inflictable_debuffs = ace_catalog_lib.get_buffs(json.entity_data['stonehearth:buffs'].inflictable_debuffs)
   end

   if json and json.entity_data and json.entity_data['stonehearth:food_container'] and json.entity_data['stonehearth:food_container'].food then
      local food_json = radiant.resources.load_json(json.entity_data['stonehearth:food_container'].food)
      if food_json and food_json.entity_data and food_json.entity_data['stonehearth:food'] and food_json.entity_data['stonehearth:food'].applied_buffs then
         catalog_data.food_buffs = ace_catalog_lib.get_buffs(food_json.entity_data['stonehearth:food'].applied_buffs)
      end
   end
end

function ace_catalog_lib.get_equipment_types(json)
   local equipment_types = {}
   local types = json.equipment_types or ace_catalog_lib._get_default_equipment_types(json)
   for _, type in ipairs(types) do
      equipment_types[type] = true
   end
   return equipment_types
end

-- other mods that want to add in additional default types can easily patch this to first call this version of the function
-- and then additionally insert their other types into the resulting table before returning it
function ace_catalog_lib._get_default_equipment_types(json)
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

function ace_catalog_lib.get_buffs(buff_data)
   local buffs = {}
   if buff_data then
      for buff, data in pairs(buff_data) do
         local uri = type(data) == 'table' and data.uri or data
         local json = radiant.resources.load_json(uri)
         if json then
            table.insert(buffs, {
               uri = uri,
               axis = json.axis,
               display_name = json.display_name,
               description = json.description,
               icon = json.icon,
               invisible_to_player = json.invisible_to_player,
               invisible_on_crafting = json.invisible_on_crafting
            })
         end
      end
   end
   return buffs
end

return ace_catalog_lib