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
      log:debug('added equipment types for %s: %s', uri, radiant.util.table_tostring(catalog_data.equipment_types))
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

return ace_catalog_lib