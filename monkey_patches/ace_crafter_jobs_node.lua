local log = radiant.log.create_logger('build.plan.crafter_jobs_node')

local CrafterJobsNode = require 'stonehearth.components.building2.plan.nodes.crafter_jobs_node'
local AceCrafterJobsNode = radiant.class('CrafterJobsNode')

function CrafterJobsNode:__init(building, items, resources, insert_craft_requests)
   self._building = building
   self._items = items
   self._resources = resources
   self._insert_craft_requests = insert_craft_requests
end

function AceCrafterJobsNode:start()
   radiant.events.trigger_async(self, 'stonehearth:build2:plan:node_complete')
   
   local player_id = radiant.entities.get_player_id(self._building)
   local should_queue = stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth', 'building_auto_queue_crafters', true)
   if not should_queue then
      return
   end

   local resource_constants = stonehearth.constants.resources

   log:debug('queuing crafting jobs for %s%s', self._building, tostring(self._insert_craft_requests) and ' (inserting at top of queue)' or '')
   local bid = self._building:get_id()

   local player_jobs_controller = stonehearth.job:get_jobs_controller(player_id)
   for resource_name, stacks in pairs(self._resources) do
      if stacks > 0 then
         local resource_constant_data = resource_constants[resource_name]
         local crafter_job = resource_constant_data and resource_constant_data.auto_queue_crafter_job
         if crafter_job and resource_constant_data.default_resource then
            local count = math.ceil(stacks / (resource_constant_data.stacks or 1))
            player_jobs_controller:request_craft_product(resource_constant_data.default_resource, count, bid, false, self._insert_craft_requests)
         end
      end
   end

   for item_uri, count in pairs(self._items) do
      if count > 0 then
         local item_data = radiant.util.split_string(item_uri, stonehearth.constants.item_quality.KEY_SEPARATOR)
         local real_uri = item_data[1]
         local quality = tonumber(item_data[2])

         player_jobs_controller:request_craft_product(real_uri, count, bid, false, self._insert_craft_requests)
      end
   end
end

return AceCrafterJobsNode
