local log = radiant.log.create_logger('build.plan.new_mining_node')
local constants = require 'stonehearth.constants'

local AceNewMiningNode = class()

function AceNewMiningNode:start()
   log:spam('starting')
   local player_id = radiant.entities.get_player_id(self._building)
   for _, mining_region in pairs(self._mining_regions) do
      local mining_zone = stonehearth.mining:dig_region(player_id, mining_region, constants.mining.purpose.BUILDING, { bid = self._building:get_id() })
      if mining_zone then
         mining_zone:add_component('stonehearth:mining_zone')
                        :set_selectable(false)

         self._mining_zones[mining_zone:get_id()] = mining_zone
         self._traces[mining_zone:get_id()] = radiant.events.listen_once(mining_zone, 'radiant:entity:destroy', self, self._on_mine_done)
      end
   end
end

function AceNewMiningNode:instamine()
   for _, z in pairs(self._mining_zones) do
      stonehearth.mining:insta_mine_zone_command(nil, nil, z:get('stonehearth:mining_zone'))
   end
end

return AceNewMiningNode
