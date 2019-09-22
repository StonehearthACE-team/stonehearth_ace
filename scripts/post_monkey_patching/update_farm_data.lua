return function()
   local farming = stonehearth and stonehearth.farming
   if farming and farming._load_field_types then
      farming:_load_field_types()
   else
      radiant.log.write_('stonehearth_ace', 0, 'update_farm_data script failed: no stonehearth.farming service initialized/patched')
   end
end