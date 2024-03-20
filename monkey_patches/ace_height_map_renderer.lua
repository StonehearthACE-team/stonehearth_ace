local AceHeightMapRenderer = class()

function AceHeightMapRenderer:get_rock_terrain_tag_at_height(height)
   local rock_layers = self._rock_layers
   local num_rock_layers = self._num_rock_layers
   local i, tag

   for i = 2, num_rock_layers do
      if rock_layers[i].max_height > height then
         return rock_layers[i-1].terrain_tag
      end
   end

   return rock_layers[num_rock_layers].terrain_tag
end

return AceHeightMapRenderer
