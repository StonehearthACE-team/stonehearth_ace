local Material = require 'stonehearth.components.material.material'
local catalog_lib = require 'stonehearth.lib.catalog.catalog_lib'

local CatalogService = class()

function CatalogService:initialize()
   -- Create a new catalog every time in case the json changed.
   self._catalog = {}
   self._shop_buyable_items = {}
   self._shop_specific_buyable_items = {}
   self._likeable_items = {}  -- Items that can be chosen to like/love/dislike by the appeal system.
   self._materials = {}
   self._all_entity_uris = {}
   self._materials_to_matching_uris = {} -- Map of material id -> uris that provide that material

   catalog_lib.load_catalog(self._catalog, function(full_alias, result)
      if result and result.catalog_data then
         if result.buyable then
            rawset(self._shop_buyable_items, full_alias, true)
         end
         if result.specific_buyable then
            rawset(self._shop_specific_buyable_items, full_alias, true)
         end
         if result.likeable then
            table.insert(self._likeable_items, full_alias)
         end
         if result.catalog_data.materials then
            local material_object = self:get_material_object(result.catalog_data.materials)
            for material_id, _ in pairs(material_object.material_subsets) do
               local entry = self._materials_to_matching_uris[material_id]
               if not entry then
                  entry = {}
                  self._materials_to_matching_uris[material_id] = entry
               end
               -- Make sure to cache both the iconic and root uri since inventory trackers
               -- use the uri of the entity's current entity form
               if result.catalog_data.iconic_uri then
                  entry[result.catalog_data.iconic_uri] = true
               end
               entry[full_alias] = true
            end
            
         end
      end

      self._all_entity_uris[full_alias] = full_alias
   end)
end

function CatalogService:get_catalog()
   return self._catalog
end

function CatalogService:get_all_entity_uris()
   return self._all_entity_uris
end

function CatalogService:get_materials_to_matching_uris()
   return self._materials_to_matching_uris
end

---Returns a table (keyed by uri) of an instance of every item in the world which is stockable.  These
-- are all the entities mentioned in the manifest of every mod which have the stonehearth:net_worth
-- entity data where shop_info.sellable = true.
function CatalogService:get_shop_buyable_items()
   return self._shop_buyable_items
end

-- ACE: returns all items that can be bought normally ("buyable": true) and also when specifying uri
-- (the "buyable" tag only makes sense for disallowing from material selectors, not uri specification)
function CatalogService:get_shop_specific_buyable_items()
   return self._shop_specific_buyable_items
end

-- Items that can be chosen to like/love/dislike by the appeal system.
function CatalogService:get_likeable_items()
   return self._likeable_items
end

function CatalogService:get_catalog_data(uri)
   return rawget(rawget(self, '_catalog'), uri)  -- hotspot
end

function CatalogService:is_item(uri)
   if self._catalog[uri] == nil then
      return false
   end
   local catalog_data = self._catalog[uri]
   return catalog_data.is_item == true
end

function CatalogService:is_material(uri, desired_materials)
   -- Hotspot
   local catalog_data = rawget(rawget(self, '_catalog'), uri)
   if not catalog_data then
      return false
   end
   local materials = rawget(catalog_data, 'materials')
   if not materials then
      return false
   end
   local material = self:get_material_object(materials)
   local lookup = self:get_material_object(desired_materials)
   return material:contains_all_parts(lookup)
end

function CatalogService:get_material_object(material_str)
   local material = rawget(self._materials, material_str)
   if not material then
      material = Material(material_str)
      rawset(self._materials, material_str, material)
   end
   return material
end

function CatalogService:is_category(uri, category)
   if self._catalog[uri] == nil then
      return false
   end
   local catalog_data = self._catalog[uri]
   return catalog_data.category == category
end

return CatalogService
