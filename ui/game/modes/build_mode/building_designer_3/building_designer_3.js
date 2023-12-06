App.StonehearthBuildingDesignerTools3 = App.View.extend({
   templateName: 'buildingDesigner3',
   uriProperty: 'model',

   buildBrushes: null,

   init: function() {
      var self = this;
      self._building_service = null;
      self._old_selected = {};
      self._old_selected_uris = {};
      self._super();

      radiant.call('stonehearth:get_client_service', 'building')
         .done(function(e) {
            self._onServiceReady(e.result);
         })
         .fail(function(e) {
            console.log('error getting building service');
            console.dir(e);
         });
   },

   didInsertElement: function() {
      var self = this;
      this._super();
      self._switchToolContext(null);
   },

   _onServiceReady: function(service) {
      var self = this;
      self._building_service = service;
      self._building_trace = radiant.trace(self._building_service).progress(function(change) {
         if (change.selection && !_.isEqual(self._old_selected, change.selection.selected)) {
            self._old_selected = _.clone(change.selection.selected);
            self._old_selected_uris = _.clone(change.selection.selected_uris);
            self._onSelectionChanged(self._old_selected, self._old_selected_uris);
         }
      });

      var tp = self._getToolPalette();
      if (tp) {
         tp.resetTool();
      }
   },

   showEditor: function() {
      this._super();
   },

   _onSelectionChanged: function(selected, uris) {
      var self = this;

      if (!self.visible()) {
         self.show();
      }

      if (_.size(selected) == 1) {
         self._switchToolContext(_.first(_.keys(uris)), selected);
      } else if (!self._currentTool || self._currentTool == 'pointerTool') {
         self._switchToolContext(null);
         self._getMaterialList().setWidgets(uris);
      }
   },

   _switchToolContext: function(uri, selected) {
      var self = this;

      radiant.each(self.get('childViews'), function(_, v) {
         if (v.toolContext != null) {
            v.hide();
         }
      });

      // this is a hack, but always update the roof tool widget when deselecting something
      var toolContext = self._getToolContext(uri) || (uri == null && self._getToolContext('stonehearth:build2:entities:roof_widget'));
      if (toolContext) {
         toolContext.setSelected(selected);
         toolContext.show();
      }

      self._getMaterialList().setSelected(selected);
   },

   _getToolContext: function(uri) {
      var self = this;

      if (uri == null) {
         return;
      }

      var result = null;
      radiant.each(self.get('childViews'), function(_, v) {
         if (v.toolContext == uri) {
            result = v;
         }
      });
      return result;
   },

   getBuildingStatusView: function() {
      var self = this;

      if (!self._buildingStatusView) {
         radiant.each(self.get('childViews'), function(_, v) {
            if (v.templateName == 'buildingStatus') {
               self._buildingStatusView = v;
            }
         });
      }

      return self._buildingStatusView;
   },

   _getMaterialList: function() {
      var self = this;

      if (!self._materialListView) {
         radiant.each(self.get('childViews'), function(_, v) {
            if (v.templateName == 'materialList') {
               self._materialListView = v;
            }
         });
      }

      return self._materialListView;
   },

   _getToolStatus: function() {
      var self = this;

      if (!self._toolStatusView) {
         radiant.each(self.get('childViews'), function(_, v) {
            if (v.templateName == 'toolStatus') {
               self._toolStatusView = v;
            }
         });
      }

      return self._toolStatusView;
   },

   _getToolPalette: function() {
      var self = this;

      if (!self._toolPaletteView) {
         radiant.each(self.get('childViews'), function(_, v) {
            if (v.templateName == 'toolPalette') {
               self._toolPaletteView = v;
            }
         });
      }

      return self._toolPaletteView;
   },

   getActiveTool: function() {
      var self = this;

      return self._currentTool;
   },

   actions: {
      toolChange: function(structureUri, toolKind) {
         var self = this;

         self._currentTool = toolKind;

         var selected = null;
         var uris = {};
         if (structureUri && structureUri != 'erase') {
            uris[structureUri] = true;
         } else if (structureUri == null) {
            // We're clearing the tool, so revert to whatever is selected.
            uris = self._old_selected_uris;
            selected = uris;
            structureUri = _.first(_.keys(uris));
         }

         self._getMaterialList().setWidgets(uris);
         self._getToolStatus().setTool(toolKind);
         self._switchToolContext(structureUri, selected);
      },

      resetTool: function() {
         var self = this;
         self._getToolPalette().resetTool();
      },

      restoreTool: function(tool) {
         var self = this;
         self._currentTool = tool;
         self._getToolPalette().restoreTool(tool);
      },

      close: function() {
         var self = this;
         if (self._getToolPalette() != null) {
            self._getToolPalette().unsetTool();
            self._getToolPalette().resetTool();
         }
         radiant.call_obj('stonehearth.building', 'clear_selected_command');
      }
   }
});
