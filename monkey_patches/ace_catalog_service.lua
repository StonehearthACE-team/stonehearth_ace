local AceCatalogService = class()

function AceCatalogService:is_item(uri)
   if self._catalog[uri] == nil then
      return false
   end
   local catalog_data = self._catalog[uri]
   -- ACE: also check to make sure we're not considering the root form for an entity that has a separate iconic form
   return catalog_data.is_item == true and uri ~= catalog_data.root_entity_uri
end

return AceCatalogService
