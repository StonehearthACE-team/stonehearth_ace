App.StonehearthBuildModeView = App.ContainerView.extend({

   fabProperties: {
     'stonehearth:fabricator' : {
         'blueprint': {
            'stonehearth:floor' : {}
         }
      }
   },

   // Sigh--keep in sync with mods/stonehearth/constants.lua
   constants : {
      ROAD: 'road',
      CURB: 'curb'
   },

   init: function() {
      this._super();

      this._builderVisible = false;

      var self = this;

      self.selectedEntityTrace = null;
   },

   didInsertElement: function() {
      var self = this;

      this._brokenBuildingDesignerView = self.addView(App.StonehearthBuildingDesignerTools);
      self._buildingDesignerView = self.addView(App.StonehearthBuildingDesignerTools3);
      this._miningView = self.addView(App.StonehearthMiningView);

      $(top).on('selected_sub_part_changed', function(_, change) {
         self._selectedSubPart = change.selected_sub_part;
         self._onStateChanged();
      });

      // track game mode changes and nuke any UI that we've show when we exit build mode
      $(top).on('mode_changed', function(_, mode) {
         self._onStateChanged();
      });

      // show the custom building editor
      $(top).on('stonehearth_building_designer', function() {
         self._showBrokenBuildingDesignerView('editor');
      });

      $(top).on('stonehearth_building_designer_new', function() {
         self._toggleBuildingDesignerView();
      });

      // ACE: track game mode changes and nuke any UI that we've shown when we exit build mode
      var prevMode;
      $(top).off('mode_changed').on('mode_changed', function(_, mode) {
         if (prevMode == 'build' || mode == 'build') {
            self._onStateChanged();
         }
         prevMode = mode;
      });

      this.hideAllViews();
   },

   hide: function() {
      this.hideAllViews();
      this._super();
   },

   // Nuke the trace on the selected entity
   destroy: function() {
      this._destroyTrace();
      this._super();
   },

   _showBrokenBuildingDesignerView: function() {
      App.setGameMode('build');
      this.hideAllViews();
      this._brokenBuildingDesignerView.show();
   },

   _toggleBuildingDesignerView: function() {
      var visible = this.visible();

      this.hideAllViews();

      if (!visible) {
         // hide the unit frame because it overlaps with the builder ui
         var unitFrame = App.gameView.getView(App.StonehearthUnitFrameView);
           if (unitFrame) {
           unitFrame.set('uri', null);
           radiant.call('stonehearth:select_entity', null);
         }
         this.show();
         App.setGameMode('build');
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:wash_in' });
         this._buildingDesignerView.show();
      } else {
         this.hide();
         App.setGameMode('normal');
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:wash_out' });
      }
   },

   _destroyTrace: function() {
      if (this.selectedEntityTrace) {
         this.selectedEntityTrace.destroy();
         this.selectedEntityTrace = null;
      }
   },

   _onStateChanged: function() {
      var self = this;

      if (App.getGameMode() == 'build') {
         if (self._selectedSubPart) {
            self._destroyTrace();
            self.selectedEntityTrace = new RadiantTrace();
            self.selectedEntityTrace.traceUri(self._selectedSubPart, self.fabProperties)
               .progress(function(entity) {
                  // if the selected entity is a building part, show the building designer
                  if (entity['stonehearth:fabricator'] || entity['stonehearth:construction_data']) {
                     self._brokenBuildingDesignerView.set('uri', entity.__self);
                     self._showBrokenBuildingDesignerView();
                  } else if (entity.uri == 'stonehearth:build:prototypes:building') {
                     // if we've selected just a building with no subparts
                     self._brokenBuildingDesignerView.set('uri', entity.__self);
                     self._showBrokenBuildingDesignerView();
                  }
                  else {
                     self._brokenBuildingDesignerView.hide();
                  }
                  self._destroyTrace();
               })
               .fail(function(e) {
                  console.log(e);
                  self._destroyTrace();
               });
         } else {
            var selected = App.stonehearthClient.getSelectedEntity();
            if (selected) {
               if (self.selectedEntityTrace) {
                  self.selectedEntityTrace.destroy();
               }
               self.selectedEntityTrace = new RadiantTrace();
               self.selectedEntityTrace.traceUri(selected)
                  .progress(function(entity) {
                     if (entity.uri == 'stonehearth:build:prototypes:building') {
                        self._brokenBuildingDesignerView.set('uri', entity.__self);
                        self._showBrokenBuildingDesignerView();
                     } else {
                        self._brokenBuildingDesignerView.set('uri', null);
                     }
                     self._destroyTrace();
                  })
                  .fail(function(e) {
                     console.log(e);
                     self._destroyTrace();
                  });
            } else {
               self._brokenBuildingDesignerView.set('uri', null);
            }
         }
      } else {
         // If we chose to get out of build mode
         // TODO(yshan) should we deselect the building?
         var selected = App.stonehearthClient.getSelectedEntity();
         var buildingDesignerSelected = self._brokenBuildingDesignerView.get('building');
         if (buildingDesignerSelected && selected == buildingDesignerSelected.__self) {
            radiant.call('stonehearth:select_entity', null);
         }

         // This might not exist, if the new builder isn't enabled.
         if (self._buildingDesignerView) {
            self._buildingDesignerView.send('close');
         }
         self._brokenBuildingDesignerView.set('uri', null);
         self._destroyTrace();
         self.hide();
      }
   }
});
