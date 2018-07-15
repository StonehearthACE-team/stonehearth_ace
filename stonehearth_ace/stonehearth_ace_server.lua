stonehearth_ace = {}

stonehearth_ace.util = require("lib.util")

local service_creation_order = {
   'crafter_info',
}

local function monkey_patching()
   local smart_craft_order_list = require('patches.smart_craft_order_list')
   local craft_order_list = radiant.mods.require('stonehearth.components.workshop.craft_order_list')
   radiant.mixin(craft_order_list, smart_craft_order_list)


   local smart_craft_order = require('patches.smart_craft_order')
   local craft_order = radiant.mods.require('stonehearth.components.workshop.craft_order')
   radiant.mixin(craft_order, smart_craft_order)


   local job_info_controller = radiant.mods.require('stonehearth.services.server.job.job_info_controller')
   job_info_controller.get_recipe_list = function(self)
      return self._sv.recipe_list
   end
end

local function create_service(name)
   local path = string.format('services.server.%s.%s_service', name, name)
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
   radiant.log.write_('stonehearth_ace', 0, 'ACE server initialized')
   stonehearth_ace._sv = stonehearth_ace.__saved_variables:get_data()

   for _, name in ipairs(service_creation_order) do
      create_service(name)
   end
end

function stonehearth_ace:_on_required_loaded()
   monkey_patching()
end

radiant.events.listen(stonehearth_ace, 'radiant:init', stonehearth_ace, stonehearth_ace._on_init)
radiant.events.listen(radiant, 'radiant:required_loaded', stonehearth_ace, stonehearth_ace._on_required_loaded)

return stonehearth_ace
