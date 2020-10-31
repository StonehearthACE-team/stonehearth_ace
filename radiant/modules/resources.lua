--[[
   ACE: overriding instead of patching because of the extensive use of local variables
   need to patch to add option to replace existing cache when loading a json
]]

local resources = {}
local cached_json = {}
local manifests = {}

function resources.__init()
   cached_json = {}
end

function resources.reset()
   resources.clear_cached_json()
   manifests = {}
   _radiant.res.reset()
end

function resources.load_animation(uri)
   return _radiant.res.load_animation(uri)
end

function resources.get_mod_list()
   return _host:get_mod_list();
end

function resources.load_json(uri, enable_caching, report_error_if_nonexistent, replace_existing_cache)
   local json
   if enable_caching or enable_caching == nil then
      -- the json loader will convert the json object to a lua table, which can be really
      -- expensive for large json objects.  maybe lua objects would get created, etc.  so
      -- cache it so we only do that conversion once.
      json = cached_json[uri]
   else
      _radiant.res.remove_from_json_cache(uri)  -- C++ has its own cache
   end
   if not json then
      json = _radiant.res.load_json(uri, report_error_if_nonexistent or report_error_if_nonexistent == nil)
      if enable_caching or enable_caching == nil or replace_existing_cache then
         cached_json[uri] = json
      end
   end
   return json
end

function resources.load_manifest(uri)
   local manifest = manifests[uri]

   if not manifest then
      manifest = _radiant.res.load_manifest(uri)
      manifests[uri] = manifest
   end

   return manifest
end

function resources.convert_to_canonical_path(uri)
   return _radiant.res.convert_to_canonical_path(uri)
end

function resources.clear_cached_json()
   cached_json = {}
end

resources.__init()
return resources
