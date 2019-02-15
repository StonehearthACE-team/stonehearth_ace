return function()
   local catalog = stonehearth and ((stonehearth.catalog and stonehearth.catalog:get_catalog())
                                 or (stonehearth.catalog_client and stonehearth.catalog_client._sv and stonehearth.catalog_client._sv.catalog))
   if catalog then
      require('stonehearth.lib.catalog.catalog_lib').update_catalog(catalog)
   end
end