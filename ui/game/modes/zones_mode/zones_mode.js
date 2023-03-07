App.StonehearthZonesModeView = App.View.extend({
   templateName: 'zonesMode',
   i18nNamespace: 'stonehearth',
   customEntityZoneViews: [],

   init: function() {
      this._super();

      var self = this;
      $(top).on("radiant_selection_changed", function (_, e) {
         self._onEntitySelected(e);
      });

      $(top).on('mode_changed', function(_, mode) {
         if (mode != 'zones') {
            if (self._propertyView) {
               self._propertyView.destroyWithoutDeselect();
            }
         }
      });

      self._components = {
         "stonehearth:storage" : {}
      };
      
      self.customEntityZoneViews.push(self._ACE_CustomZoneViews)
   },

   didInsertElement: function() {
      this.$().hide();
   },

   destroy: function() {
      if (this.selectedEntityTrace) {
         this.selectedEntityTrace.destroy();
         this.selectedEntityTrace = null;
      }

      this._super();
   },

   _onEntitySelected: function(e) {
      var self = this;
      var entity = e.selected_entity

      // nuke the old trace
      if (self.selectedEntityTrace) {
         self.selectedEntityTrace.destroy();
         self.selectedEntityTrace = null;
      }

      if (!entity) {
         return;
      }

      // trace the properties so we can tell if we need to popup the properties window for the object
      self.selectedEntityTrace = new RadiantTrace(entity, self._components)
         .progress(function(result) {
            self._examineEntity(result);
         })
         .fail(function(e) {
            console.log(e);
         });
   },

   // ACE: examine more components of the entity
   _examineEntity: function(entity) {
      var self = this;
      if (!entity && self._propertyView) {
         self._propertyView.destroyWithoutDeselect();
         self._propertyView = null;
         return;
      }

      var viewType = null;
      var matchesPlayerId = entity.player_id == App.stonehearthClient.getPlayerId();
      if (entity['stonehearth:player_market_stall']) {
         viewType = App.StonehearthPlayerMarketStallView;
      } else if (entity['stonehearth:storage'] && entity['stonehearth:storage'].is_public && !entity['stonehearth:storage'].is_hidden) {
         // TODO: sigh, the above is probably wrong, but highly convenient.
         viewType = App.StonehearthStockpileView;
      } else if (entity['stonehearth:farmer_field']) {
         viewType = App.StonehearthFarmView;
      } else if (entity['stonehearth:trapping_grounds']) {
         viewType = App.StonehearthTrappingGroundsView;
      } else if (entity['stonehearth:mining_zone']) {
         viewType = App.StonehearthMiningZoneView;
      } else if (entity['stonehearth:shepherd_pasture']) {
         viewType = App.StonehearthPastureView;
      } else if (entity['stonehearth_ace:universal_storage']) {
         viewType = false;
         radiant.call_obj('stonehearth_ace.universal_storage', 'get_storage_from_access_node_command', entity.__self)
            .done(function (response) {
               if (self.isDestroyed || self.isDestroying) {
                  return;
               }
               self._showZoneUi(response.storage, App.StonehearthStockpileView);
            });
      } else {
         viewType = self._getCustomZoneView(entity, matchesPlayerId);
      }

      if (viewType) {
         self._showZoneUi(entity, viewType);
      } else if (viewType === null) {
         if (self._propertyView) {
            self._propertyView.destroyWithoutDeselect();
            self._propertyView = null;
         }
      }
   },

   // ACE: override this to not set the game mode; that should already be happening elsewhere
   _showZoneUi: function(entity, viewType) {
      var self = this;

      if (self._propertyView && (self._propertyView.constructor != viewType || self._propertyView.isDestroyed)) {
         self._propertyView.destroyWithoutDeselect();
         self._propertyView = null;
      };

      var uri = typeof(entity) == 'string' ? entity : entity.__self;
      if (!self._propertyView) {
         self._propertyView = App.gameView.addView(viewType, { uri: uri });
      } else {
         self._propertyView.set('uri', uri);
      }
      //App.setGameMode('zones');
   },

   _getCustomZoneView: function(entity, matchesPlayerId) {
      var self = this;
      for (var i = 0; i < self.customEntityZoneViews.length; i++)
      {
         var mode = self.customEntityZoneViews[i](entity, matchesPlayerId);
         if (mode) {
            return mode;
         }
      }
      
      return null;
   },

   // modders can override this function to add their own custom entity zone views
   _ACE_CustomZoneViews: function(entity, matchesPlayerId) {
      if (entity['stonehearth_ace:guard_zone']) {
         return App.StonehearthAceGuardZoneView;
      }
      else if (entity['stonehearth_ace:herbalist_planter'] && matchesPlayerId) {
         return App.AceHerbalistPlanterView;
      }
      else if (entity['stonehearth_ace:periodic_interaction'] &&
            (matchesPlayerId || entity['stonehearth_ace:periodic_interaction'].allow_non_owner_player_interaction)) {
         return App.AcePeriodicInteractionView;
      }

      return null;
   }
});
