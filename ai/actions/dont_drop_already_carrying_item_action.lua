local Entity = _radiant.om.Entity
local DontDropAlreadyCarryingItem = class()

DontDropAlreadyCarryingItem.name = 'drop and pickup item'
DontDropAlreadyCarryingItem.does = 'stonehearth_ace:drop_and_pickup_item'
DontDropAlreadyCarryingItem.args = {
   found_item = Entity,
   found_rating = {
      type = 'number',
      default = 1
   },
   carrying_rating = {
      type = 'number',
      default = 0
   }
}
DontDropAlreadyCarryingItem.think_output = {
   item = Entity,
}
DontDropAlreadyCarryingItem.priority = 1

local log = radiant.log.create_logger('dont_drop')

function DontDropAlreadyCarryingItem:start_thinking(ai, entity, args)
   local carrying = ai.CURRENT.carrying
   local rating = args.carrying_rating
   if carrying and rating and rating >= args.found_rating then
      ai:set_think_output({item = carrying})
      --log:debug('don\'t drop, dead inside')
   end
end

return DontDropAlreadyCarryingItem
