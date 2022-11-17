local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local rng = _radiant.math.get_default_rng()
local log = radiant.log.create_logger('loot_table')

local LootTable = require 'stonehearth.lib.loot_table.loot_table'
local AceLootTable = class()

function AceLootTable:__init(json, quality_override, filter_script, filter_args)
   self:_clear()
   self._filter_script = filter_script
   self._loaded_filter_script = radiant.util.is_string(filter_script) and radiant.mods.load_script(filter_script) or filter_script or {}
   self._filter_args = filter_args or {}
   self:_load_from_json(json, quality_override)
end

--[[
Sample json:
{
   "entries": {
      "entry_1": {
         "roll_type": "some_of",
         "num_rolls" : {
            "min" : 2,
            "max" : 4
         },
         "quality": 2,
         "items": {  --why is this "[" vs "{"?
            "copper": {
               "type" : "item",
               "uri": "stonehearth:copper_coin",
               "num_rolls": 5,
               "weight": 10,
               "quality": 2
            },
            "loot_bag_tier_2_generic_1": {
               "type" : "bag",
               "uri": "stonehearth:loot_bag:tier_2:generic",
               "weight": 1,
               "quality": [
                  [
                     4,
                     0.01
                  ],
                  [
                     3,
                     0.05
                  ],
                  [
                     2,
                     0.5
                  ]
               ]
            },
            "bed": {
               "uri": "stonehearth:furniture:comfy_bed",
               "num_rolls": {
                  "min" : 2,
                  "max" : 4
               },
               "weight": 1
            },
            "loot_bag_high_quality_tier_2": {
               "type" : "bag",
               "uri": "stonehearth:loot_bag:tier_2",
               "weight": 1
            }
         }
      },
      "entry_2": {
         "items": {
            "none": {
               "weight": 100
            },
            "gold": {
               "uri": "stonehearth:gold_coin",
               "weight": 1
            }
         }
      }
   }
}

------------------------------------------------

"entries":
   a dictionary of loot table entries.  Each entry has the following:
   "roll_type":
      a) Can be a string of either "each_of" or "some_of"
      b) "each_of" will cause all entries and items below this point to be added to a list to give to the player as loot.
      b) "some_of" will cause either single or multiple random entries or items listed in the "entry" to be added to a list to give to the player as loot based on the "num_rolls" value.
      c) Can be omitted (which will default to "some_of")

   "num_rolls" :
      a) Can be a table with keys "min" and "max"
      b) Can be a number
      c) Can be omitted (which will default to 1)
      d) When the type "each_of" is used, this value applies to all # of drops per item within it.

   "items":
      a) Dictionary mapping of unique string name (make something up!) to entries with keys "type", "uri", "weight", and "num_rolls"
      b) If "type" is not included, it defaults to "item".
      c) If "type" is included, it must be of type "item" or "bag".
         a) "item" type is a link to a uri for an item (a chair, a bed, a weapon).
         b) "bag" type is a link to a uri for another list of items/bags (another loot_table just like this one).
      d) If unique string name is "none" or "uri" is the empty string, no drop is created if it is rolled
      e) If "weight" is omitted, defaults to 1. Non-integer values are ok.
      f) "num_rolls":
         a) Can be a table with keys "min" and "max"
         b) Can be a number
         c) Can be omitted (which will default to 1)

------------------------------------------------

You can also use this to specify that 3 separate items are always dropped.
Ex: remove the none entry from extra_drop_1 and then it will always drop gold.


--]]

------------------------------------------------

--working out code 

function AceLootTable:_load_from_json(json, quality_override)
   if not json or not json.entries then
      self:_clear()
      return
   end

   local entry_filter_fn = self._loaded_filter_script.filter_entry
   local item_filter_fn = self._loaded_filter_script.filter_item
   local filter_args = self._filter_args

   for name, data in pairs(json.entries) do
      if not entry_filter_fn or entry_filter_fn(filter_args, data) then
         local entry = nil

         entry = {
            roll_type = 'some_of',
            num_rolls = 1,
            items = nil
         }
         entry.num_rolls = self:_determine_num_rolls(data.num_rolls)
         
         if data.roll_type then
            entry.roll_type = data.roll_type
         end
         
         --If 'some_of' then randomly select with weigthedset
         if entry.roll_type == 'some_of' then
            entry.items = WeightedSet(rng)
         --Elseif 'each_of' then select all with a table
         elseif entry.roll_type == 'each_of' then
            entry.items = {}
         end

         for items_name, items_entry in pairs(data.items) do
            local out_item_type = 'item'
            local loc_item_uri = nil
            local entry_data = nil

            if items_entry.type then
               out_item_type = items_entry.type
            end

            items_entry.num_rolls = self:_determine_num_rolls(items_entry.num_rolls)

            if items_entry.uri then
               loc_item_uri = items_entry.uri
            elseif items_name == 'none' or items_name == '' then
               loc_item_uri = ''
            else
               log:error('no uri')
            end

            entry_data = {
               item_uri = loc_item_uri,
               num_rolls = items_entry.num_rolls,
               item_type = out_item_type,
               quality_fn = self:_get_quality_fn(quality_override, items_entry.quality or data.quality or 1)
            }

            if not item_filter_fn or item_filter_fn(filter_args, items_entry, entry_data) then
               --If 'some_of' then randomly select with weigthedset
               if entry.roll_type == 'some_of' then
                  entry.items:add(entry_data, items_entry.weight or 1)
               --Elseif 'each_of' then select all with a table
               elseif entry.roll_type == 'each_of' then
                  table.insert(entry.items, entry_data)
               end
            end
         end

         table.insert(self._entries, entry)
      end
   end
end

function AceLootTable:_get_quality_fn(quality_override, quality)
   -- quality_override and quality could each be a table or a number, and quality_override could also be nil or a higher level quality function
   -- even if no tables are present, we still want to use item_quality_lib to ensure respect for max quality
   return function()
      local q = 1
      if type(quality_override) == 'function' then
         q = quality_override()
      elseif quality_override and (type(quality_override) == 'table' or quality_override > 1) then
         q = item_quality_lib.get_quality(quality_override)
      end
      return math.max(q, item_quality_lib.get_quality(quality))
   end
end

-- Returns a table of uri, quantity
function AceLootTable:roll_loot(inc_recursive_uri_storage)
   local uris = {}
   local uris_interim = {}

   for i, entry in pairs(self._entries) do
      if entry.num_rolls > 0 then
         for i = 1, entry.num_rolls do
            if entry.roll_type == 'each_of' then
               for entryname, entryvalue in pairs(entry.items) do
                  local uri = {}
                  uri = {
                     item_uri = entryvalue.item_uri,
                     item_type = entryvalue.item_type,
                     num_rolls = entryvalue.num_rolls,
                     quality_fn = entryvalue.quality_fn
                  }
                  
                  if uri and uri.item_uri ~= '' then
                     --this should be where we use num_rolls to add multiple of the same thing
                     uris_interim[uri] = (uris_interim[uri] or 0) + uri.num_rolls
                  end
               end
            
            elseif entry.roll_type == 'some_of' then
               --Changing this to 'choose_random_entry' breaks what 'uris' is supposed to be, must fix later
               local uri = {}
               local inc_item = entry.items:choose_random()
               if inc_item then
                  uri = {
                     item_uri = inc_item.item_uri,
                     item_type = inc_item.item_type,
                     num_rolls = inc_item.num_rolls,
                     quality_fn = inc_item.quality_fn
                  }
                     
                  if uri and uri.item_uri ~= '' then
                     --this should be where we use num_rolls to add multiple of the same thing
                     for count = 1, uri.num_rolls do
                        local quantity = (uris_interim[uri] or 0) + 1
                        uris_interim[uri] = quantity
                     end
                  end
               end
            end
         end
      end
   end
   
   --Need to verify that there are no 'bag' type item entries.
   -- If there are, wipe the tables, and recursively load the function with the new .json
   -- while keeping the old information to add them together at the end.
   for key, value in pairs (uris_interim) do
      if key.item_type == 'item' then
         --if it is an 'item', then just save out the uri in uris - this cleans uris back to what it should be.
         --this 'for loop' accounts for multiple of the same key.item_uri
         
         local item = uris[key.item_uri]
         if not item then
            item = {}
            uris[key.item_uri] = item
         end
         
         -- roll the quality for each item
         for i = 1, value do
            local quality = key.quality_fn()
            item[quality] = (item[quality] or 0) + 1
         end

      elseif key.item_type == 'bag' then
         local bool_is_not_looping = true
         local recursive_uri_storage = {}

         --If it is a 'bag', then call roll_loot on the passed in uri (non-uris are not allowed)
         --Store any entry which we receive and decide to go into, and compare versus any entry which we are thinking of going into.
         -- If we find a match, cancel our dive.
         if inc_recursive_uri_storage then
            --check every entry into the previous storage
            for keycheck, valuecheck in pairs (inc_recursive_uri_storage) do
               --if the current entry is the same as any previous entries
               if key.item_uri == keycheck.item_uri then
                  --then skip everything else, ignore this loot call, and throw an error
                  bool_is_not_looping = false
               end
            end

            --otherwise we haven't seen this loot bag before and we should continue searching for items.
            --so restore the previous storage
            recursive_uri_storage = inc_recursive_uri_storage
         end

         if bool_is_not_looping then
            recursive_uri_storage[key] = value
            local recursive_uris = nil
            -- roll the quality for the bag first to pass in as an override (minimum)
            local bag = LootTable(radiant.deep_copy(radiant.resources.load_json(key.item_uri, true)), key.quality_fn(), self._filter_script, self._filter_args)
            recursive_uris = bag:roll_loot(recursive_uri_storage)
            
            --add the recursive_uris found back into the rest of the uris found.
            for recursive_key, recursive_value in pairs(recursive_uris) do

               local item = uris[recursive_key]
               if not item then
                  item = {}
                  uris[recursive_key] = item
               end
               
               for quality, quantity in pairs(recursive_value) do
                  -- roll the quality for each item
                  for i = 1, quantity do
                     local quality = recursive_key.quality_fn()
                     item[quality] = (item[quality] or 0) + 1
                  end
               end
            end
         else
            log:error('detected endless loop with recursive_uri_storage: %s', recursive_uri_storage)
         end
      end
   end

   return uris
end

return AceLootTable
