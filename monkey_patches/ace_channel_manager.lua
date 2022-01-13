--[[
   everywhere that we're accessing the water component of an entity, instead access our new water source component
]]

local AceChannelManager = class()

function AceChannelManager:_update_link(link)
   if not link.to_entity then
      return
   end

   local from_water_component = link.from_entity:add_component('stonehearth_ace:water_source')
   local from_height = from_water_component:get_water_level()
   local from_oscillations = from_water_component:get_num_oscillations()
   local to_water_component = link.to_entity:add_component('stonehearth_ace:water_source')
   local to_height = to_water_component:get_water_level()
   local to_oscillations = to_water_component:get_num_oscillations()

   local max_oscillations = math.max(from_oscillations, to_oscillations)
   local damping_factor = self:_calculate_damping_factor(max_oscillations)

   self:_update_channels(link, from_height, to_height)
   self:_update_link_capacity(link, from_height, to_height, damping_factor)

   -- must call right after updating link capacity
   self:_remove_empty_vertical_waterfalls(link)
end

function AceChannelManager:_remove_empty_vertical_waterfalls(link)
   local from_water_component = link.from_entity:add_component('stonehearth_ace:water_source')

   for key, channel in pairs(link.waterfall_channels) do
      -- is a vertical waterfall that has emptied?
      if channel.capacity == 0 and channel.from_point.y > channel.to_point.y then
         -- remove the empty block from the water region so it doesn't float indefinitely in midair
         from_water_component:remove_point_from_region(channel.from_point)
      end
   end
end

function AceChannelManager:fill_links(links, rate)
   assert(rate >= 0 and rate <= 1)

   for _, link in pairs(links) do
      local water_level = link.from_entity:add_component('stonehearth_ace:water_source'):get_water_level()
      for key, channel in pairs(link.waterfall_channels) do
         local waterfall_component = channel.entity:add_component('stonehearth:waterfall')
         if waterfall_component then
            channel.volume = channel.volume + rate * channel.capacity
            waterfall_component:set_volume(channel.volume)
            waterfall_component:set_source_water_level(water_level)
         end
      end

      link.pressure_channels.volume = link.pressure_channels.volume + rate * link.pressure_channels.capacity
   end
end

function AceChannelManager:add_water_to_waterfall_channel(channel, volume)
   local water_level = channel.from_entity:add_component('stonehearth_ace:water_source'):get_water_level()
   local waterfall_component = channel.entity:add_component('stonehearth:waterfall')
   if waterfall_component then
      channel.volume = channel.volume + volume
      channel.capacity = channel.volume
      waterfall_component:set_volume(channel.volume)
      waterfall_component:set_source_water_level(water_level)

      -- at some point we might want to limit how much water can be put into a waterfall
      return 0
   else
      return volume
   end
end

-- from_point is a point inside the source water body
-- to_point is a point at the top of the waterfall adjacent to the from_point
function AceChannelManager:add_waterfall_channel(from_point, to_point, from_entity, to_entity)
   radiant.verify(from_point.y >= to_point.y, 'unsupported upwards waterfall %s -> %s', from_point, to_point)

   local channel = self:get_waterfall_channel(from_point, to_point, from_entity, to_entity)
   if channel then
      return channel
   end

   if not to_entity and from_point.y >= to_point.y then
      local target_location
      to_entity, target_location = stonehearth.hydrology:get_waterfall_target(to_point)

      if to_entity == from_entity then
         -- waterfall source and target are the same entity
         to_entity = stonehearth.hydrology:separate_point_from_water_body(from_entity, target_location)
      end
   end
   
   local waterfall = self:_create_waterfall_entity(from_point, to_point)
   
   -- to_entity allowed to be nil here
   channel = self:_create_channel(from_point, to_point, from_entity, to_entity)
   channel.entity = waterfall
   channel.capacity = 0
   channel.volume = 0

   local from_water_component = from_entity:add_component('stonehearth_ace:water_source')
   local from_height = from_water_component:get_water_level()
   self:_update_waterfall_capacity(channel, from_height)
   local link = self:get_link(channel.from_entity, channel.to_entity, true)
   self:_add_waterfall_channel_to_link(link, channel)
   return channel
end

return AceChannelManager
