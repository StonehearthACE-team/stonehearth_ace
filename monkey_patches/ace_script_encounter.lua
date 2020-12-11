local AceScriptEncounter = class()

function AceScriptEncounter:get_out_edge()
   local script = self._sv.script
   return script and script.get_out_edge and script:get_out_edge()
end

return AceScriptEncounter
