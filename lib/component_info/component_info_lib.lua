local component_info_lib = {}

function component_info_lib.create_list(items)
   local list = {
      type = 'list',
      items = {}
   }

   for _, item in pairs(items) do
      table.insert(list.items, {
         uri = item:get_uri(),   -- can get name/description/icon from catalog
         quality = radiant.entities.get_item_quality(item)
      })
   end

   return list
end

return component_info_lib