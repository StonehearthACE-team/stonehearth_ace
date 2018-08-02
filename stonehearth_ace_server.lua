stonehearth_ace = {}

stonehearth_ace.util = require("lib.util")

local service_creation_order = {
   'crafter_info',
   'water_pump'
}

local monkey_patches = {
   ace_craft_order_list = 'stonehearth.components.workshop.craft_order_list',
   ace_craft_order = 'stonehearth.components.workshop.craft_order',
   ace_door_component = 'stonehearth.components.door.door_component',
   ace_portal_component = 'stonehearth.components.portal.portal_component',
   ace_town_patrol_service = 'stonehearth.services.server.town_patrol.town_patrol_service',
   ace_job_component = 'stonehearth.components.job.job_component',
   ace_equipment_piece_component = 'stonehearth.components.equipment_piece.equipment_piece_component',
   ace_farmer_field_component = 'stonehearth.components.farmer_field.farmer_field_component',
   ace_growing_component = 'stonehearth.components.growing.growing_component',
   ace_shepherd_pasture_component = 'stonehearth.components.shepherd_pasture.shepherd_pasture_component',
   ace_shepherd_service = 'stonehearth.services.server.shepherd.shepherd_service'
}

local function monkey_patching()
   for from, into in pairs(monkey_patches) do
      
      local monkey_see = require('monkey_patches.' .. from)
      local monkey_do = radiant.mods.require(into)
      radiant.mixin(monkey_do, monkey_see)
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
   stonehearth_ace._sv = stonehearth_ace.__saved_variables:get_data()

   for _, name in ipairs(service_creation_order) do
      create_service(name)
   end

   radiant.log.write_('stonehearth_ace', 0, 'ACE server initialized')
end

function stonehearth_ace:_on_required_loaded()
   monkey_patching()
end

radiant.events.listen(stonehearth_ace, 'radiant:init', stonehearth_ace, stonehearth_ace._on_init)
radiant.events.listen(radiant, 'radiant:required_loaded', stonehearth_ace, stonehearth_ace._on_required_loaded)

return stonehearth_ace
