local Point3 = _radiant.csg.Point3

local AceLadderBuilder = class()

function AceLadderBuilder:get_ladder_proxy()
   return self._sv.ladder_dst_proxy
end

-- ACE: don't remove the command; use it to toggle build mode instead
function AceLadderBuilder:remove_user_extension(player_id)
   -- set this before calling destroy on the handle, since that will update the build mode
   self._sv.user_requested_removal = player_id

   local toggle = false
   if self._sv.user_extension_handle then
      self._sv.user_extension_handle:destroy()
      self._sv.user_extension_handle = nil
      self.__saved_variables:mark_changed()
   else
      toggle = true
   end

   -- removing any point may end up destroying the ladder builder.
   -- if that happens, just bail right away
   if not self._sv.ladder then
      return
   end

   self:_update_build_mode(toggle)
   -- force update the teardown effect because if build mode is already teardown
   -- which it will be when the ladder is finished, then mode == mode and build mode won't update
   self:_update_teardown_effect()
end

function AceLadderBuilder:_update_build_mode(toggle)
   local climb_to = self:_get_climb_to()
   local desired_height = climb_to and climb_to.y + 1 or 0

   local actual_height = self:_get_actual_ladder_height()

   local ladder_component = self._sv.ladder:get_component('stonehearth:ladder')
   
   local height = (toggle and self._sv._build_mode == 'teardown' and actual_height) or desired_height
   ladder_component:set_desired_height(height)

   self._log:spam('desired height of ladder is now %d (actual:%d)', desired_height, actual_height)

   if toggle or desired_height ~= actual_height then
      stonehearth.ai:reconsider_entity(self._sv.ladder_dst_proxy, 'ladder height changed')
   end

   if desired_height > actual_height then
      -- build ladder
      self:_update_ladder_dst_proxy_region(desired_height, true)
      self:set_build_mode('build')
   else
      if not self:vpr_is_empty() then
         -- teardown ladder
         -- only user requested ladders can be removed from the top
         local allow_top_destination = self._sv.user_requested_removal ~= ''
         local top = self:get_vpr_top() + Point3.unit_y
         self:_update_ladder_dst_proxy_region(top.y, allow_top_destination)

         local mode = (toggle and self._sv._build_mode == 'teardown' and 'build') or 'teardown'
         --self._log:error('%s %s build mode to %s', self._sv.ladder, toggle and 'toggling' or 'setting', mode)
         self:set_build_mode(mode)
      else
         -- destroy ladder
         self:set_build_mode(nil)
         self:_check_if_valid()
      end
   end
end

return AceLadderBuilder