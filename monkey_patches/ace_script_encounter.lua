local AceScriptEncounter = class()

function AceScriptEncounter:get_out_edge()
   local script = self._sv.script
   local out_edge = script and script.get_out_edge and script:get_out_edge()
   if not out_edge then
      local encounter = self._sv.ctx.encounter
      local info = encounter and encounter:get_info()
      out_edge = info and info.out_edge
   end

   return out_edge
end

return AceScriptEncounter
