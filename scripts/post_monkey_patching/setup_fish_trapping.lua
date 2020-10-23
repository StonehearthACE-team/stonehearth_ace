return function()
   local trapping = stonehearth and stonehearth.trapping
   if trapping and trapping._setup_fish_trapping then
      trapping:_setup_fish_trapping()
   else
      radiant.log.write_('stonehearth_ace', 0, 'setup_fish_trapping script failed: no stonehearth.trapping service initialized/patched')
   end
end