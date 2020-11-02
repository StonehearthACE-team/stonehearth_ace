local AceGhostFormComponent = class()

function AceGhostFormComponent:can_iconic_be_used(uri)
   local placement_info = self._sv.placement_info
   if placement_info then
      if uri == placement_info.iconic_uri then
         return true
      end
      if not placement_info.require_exact then
         local alternates = radiant.entities.get_alternate_uris(placement_info.iconic_uri)
         return alternates[uri]
      end
   end

   return false
end

return AceGhostFormComponent
