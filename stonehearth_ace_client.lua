
-- Why this is a copy of the server script?
-- Shouldn't this be a client script?
-- Like the one in Rayya or NA mods?
-- Paul: as far as I can tell, the only stuff it was really missing from the stonehearth_client.lua script
--    was the on_server_ready stuff that I just now added. (The other stuff is generic stuff, but if you
--    see something else we should add, by all means, go ahead. I didn't look at RC or NA.)
--    So the thing about the monkey-patches is that if you use a component (like the portal_component below)
--    with both server and client services/scripts, you have to monkey-patch it in both places. The alternative
--    is to replace the file completely in the manifest, but as we know that limits compatibility with other mods.

stonehearth_ace = {}

stonehearth_ace.util = require("lib.util")

local service_creation_order = {
   'heatmap'
}

local monkey_patches = {
   ace_portal_component = 'stonehearth.components.portal.portal_component'
}

local function monkey_patching()
   for from, into in pairs(monkey_patches) do
      local monkey_see = require('monkey_patches.' .. from)
      local monkey_do = radiant.mods.require(into)
      radiant.mixin(monkey_do, monkey_see)
   end
end

local function create_service(name)
   local path = string.format('services.client.%s.%s_service', name, name)
   local service = require(path)()

   local saved_variables = stonehearth_ace._sv[name]
   if not saved_variables then
      saved_variables = radiant.create_datastore()
      stonehearth_ace._sv[name] = saved_variables
   end

   service.__saved_variables = saved_variables
   service._sv = saved_variables:get_data()
   saved_variables:set_controller(service)
   saved_variables:set_controller_name('stonehearth_ace:' .. name)
   service:initialize()
   stonehearth_ace[name] = service
end

function stonehearth_ace:_on_init()
   stonehearth_ace._sv = stonehearth_ace.__saved_variables:get_data()

   for _, name in ipairs(service_creation_order) do
      create_service(name)
   end

   radiant.events.listen(radiant, 'radiant:client:server_ready', function()
      for _, name in ipairs(service_creation_order) do
         if stonehearth_ace[name].on_server_ready then
            stonehearth_ace[name]:on_server_ready()
         end
      end
   end)

   radiant.log.write_('stonehearth_ace', 0, 'ACE client initialized')
end

function stonehearth_ace:_on_required_loaded()
   monkey_patching()
end

radiant.events.listen(stonehearth_ace, 'radiant:init', stonehearth_ace, stonehearth_ace._on_init)
radiant.events.listen(radiant, 'radiant:required_loaded', stonehearth_ace, stonehearth_ace._on_required_loaded)

return stonehearth_ace
