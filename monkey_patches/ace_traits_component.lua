local AceTraitsComponent = class()

function AceTraitsComponent:activate()
   self._json = radiant.entities.get_json(self)
end

function AceTraitsComponent:apply_base_traits()
   if self._json and self._json.base_traits then
      for trait, args in pairs(self._json.base_traits) do
         if args then
            self:add_trait(trait, type(args) == 'table' and args)
         end
      end
   end
end

function AceTraitsComponent:get_trait_stats()
   local max_traits = 3
   local gaussian_rate = 0.6

   if self._json then
      if self._json.max_traits then
         max_traits = self._json.max_traits
      end
      if self._json.gaussian_rate then
         gaussian_rate = self._json.gaussian_rate
      end
   end

   return max_traits, gaussian_rate
end

return AceTraitsComponent
