local UnderfieldLayerExtractor = radiant.class()

function UnderfieldLayerExtractor:extract_arguments(data)
   local undercrop_uri = data.args.underfield_layer:get_component('stonehearth_ace:grower_underfield_layer'):get_grower_underfield():get_undercrop_details().uri
   return { uri = undercrop_uri }
end

return UnderfieldLayerExtractor
