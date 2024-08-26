local AceCatalogClientService = class()

function AceCatalogClientService:get_catalog_data(uri)
   return self._sv.catalog[uri]
end

return AceCatalogClientService
