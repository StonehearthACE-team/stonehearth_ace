var StonehearthCatalog;

(function () {
   StonehearthCatalog = SimpleClass.extend({

      _components: {
      },

      init: function(initCompletedDeferred) {
         var self = this;
         self._initCompleteDeferred = initCompletedDeferred;
         self._catalogData = {};

         self._filteredCatalogData = {};

         $(document).on('stonehearthReady', function() {
            radiant.call('stonehearth:get_client_service', 'catalog_client')
               .done(function(response) {
                  self._catalogServiceUri = response.result;
                  self._initCompleteDeferred.resolve();
                  self._createGetterTrace();
               });
         });
      },

      getCatalogData: function(uri) {
         if (!this._catalogData) {
            return null;
         }
         return this._catalogData[uri];
      },

      // added for ACE:
      getAllCatalogData: function() {
         return this._catalogData;
      },

      getFilteredCatalogData: function(key, filterFn) {
         var self = this;
         
         if (self._filteredCatalogData[key]) {
            return self._filteredCatalogData[key];
         }

         var filtered = {};
         radiant.each(self._catalogData, function(k, v) {
            if (filterFn(k, v)) {
               filtered[k] = v;
            }
         });
         self._filteredCatalogData[key] = filtered;
         return filtered;
      },

      getUri: function() {
         return this._catalogServiceUri;
      },

      getComponents: function() {
         return this._components;
      },

      // easy, instant access to some commonly used variables (e.g. when we need to save a game).
      // NOT useful for implementing a reactive ui!  make your own trace for that!!
      _createGetterTrace: function() {
         var self = this;
         self._getterTrace = new RadiantTrace(self._catalogServiceUri, self._components)
            .progress(function(catalog_service) {
               self._catalogData = catalog_service.catalog;
            });
      }
   });

})();
