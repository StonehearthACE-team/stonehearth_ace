App.StonehearthBuildingMaterialListView = App.View.extend({
   templateName: 'materialList',
   structureKind: null,
   material: null,
   tabKeyToId : {},
   selectedBrushes : {},
   structures: ['wall', 'column', 'floor', 'voxel', 'roof', 'stairs'],
   uriProperty: 'model',

   components: {
      'stonehearth:build2:roof_widget': {},
      'stonehearth:build2:room_widget': {},
      'stonehearth:build2:wall_widget': {},
      'stonehearth:build2:stairs_widget': {},
      'stonehearth:build2:perimeter_wall_widget': {},
      'stonehearth:build2:blocks_widget': {},
      'stonehearth:build2:sub_blocks_widget': {},
      'stonehearth:build2:road_widget': {}
   },

   lastSelectedStructure: {
      'stonehearth:build2:roof_widget': 'roof',
      'stonehearth:build2:room_widget': 'floor',
      'stonehearth:build2:wall_widget': 'wall',
      'stonehearth:build2:stairs_widget': 'stairs',
      'stonehearth:build2:perimeter_wall_widget': 'wall',
      'stonehearth:build2:blocks_widget': 'voxel',
      'stonehearth:build2:sub_blocks_widget': 'voxel',
      'stonehearth:build2:road_widget': 'floor'
   },

   init: function() {
      var self = this;
      self._buildBrushes = {};
      self._materials = {};
      self._brushToMaterial = {};
      self._materialToBrush = {};
      self._super();

      self._traceBrushes = new StonehearthDataTrace('stonehearth:build:brushes')
         .progress(function(response) {
            _.forEach(response, function(data, key) {
               if (!$.isPlainObject(data)) {
                  return;
               }
               if (key == "type") {
                  return;
               }
               self._buildBrushes[key] = data;
               _.forEach(data, function(brush_kind, material) {
                  if (material == '-no material-') {
                     return;
                  }

                  self._materials[material] = true;
                  if (!self._materialToBrush[material]) {
                     self._materialToBrush[material] = [];
                  }
                  _.forEach(brush_kind, function(brush_list) {
                     if (!$.isPlainObject(brush_list)) {
                        return;
                     }

                     _.forEach(brush_list, function(__, brush_name) {
                        self._brushToMaterial[brush_name.toLowerCase()] = material;
                        self._materialToBrush[material].push(brush_name.toLowerCase());
                     });
                  });
               });
            });

            self._tracePopulation = App.population.getTrace();
            self._tracePopulation.progress(function(response) {
               var populationData = App.population.getPopulationData();
               if (populationData && populationData.kingdom) {
                  self._firstMaterial = populationData.kingdom.default_material;
               } else {
                  self._firstMaterial = 'wood resource';
               }
               Ember.run.scheduleOnce('afterRender', self, self.brushesReady);
               Ember.run.scheduleOnce('afterRender', self, '_updateMaterialListTooltips');
               self._tracePopulation.destroy();
               self._tracePopulation = null;
            });

            // Construct 'resource' buttons that run down the side.
            self._buildResources();

            // Construct the actual lists of brushes for each kind of structure.
            self._buildBrushLists(self.structures);

            self._updateTooltips();

            self._traceBrushes.destroy();
            self._traceBrushes = null;

         });
   },

   destroy: function() {
      var self = this;
      self._populationTrace.destroy();
      self._populationTrace = null;
   },

   _updateTooltips: function() {
      var self = this;

      self.$('.brush').each(function() {
          var tooltipString = $(this).attr('tooltip');
          var tooltipContent = $('<div></div>').html(tooltipString);  // Create a div and set its content to the tooltip string
          $(this).tooltipster({
              content: tooltipContent,
              contentAsHTML: true
          });
      });
   },

   brushesReady: function() {
      var self = this;

      var firstMaterial = self._firstMaterial;
      if (!self._materials[firstMaterial]) {
         firstMaterial = _.first(_.keys(self._materials));
      }

      var firstBrush = _.first(self._materialToBrush[firstMaterial]);
      _.forEach(self.structures, function(structure) {
         self.setBrush(structure, self._getFirstBrush(firstMaterial, structure));
      });
      self.setWidgets({});
   },

   didInsertElement: function() {
      var self = this;
      this._super();
   },

   _updateMaterialListTooltips: function() {
      var self = this;

      self.$('.brush').each(function() {
          var tooltipString = $(this).attr('tooltip');
          var tooltipContent = $('<div></div>').html(tooltipString);  // Create a div and set its content to the tooltip string
          $(this).tooltipster({
              content: tooltipContent,
              contentAsHTML: true
          });
      });
  },

   _onSelectionChange: function() {
      var self = this;

      var widget = self.get(self.uriProperty);

      if (!widget) {
         return;
      }

      _.forEach(self.components, function(v, k) {
         if (widget[k]) {
            var widgets = {};
            widgets[widget.uri] = true;

            self.setWidgets(widgets);
            var widget_data = widget[k];
            if (widget_data.__fields) {  // If using SV tables, the data is stored under __fields.
               widget_data = widget_data.__fields;
            }

            if (widget_data) {
               self._setSelectedBrushes(k, widget_data);
            }
            return true;
         }
      });
   }.observes('model'),

   _setSelectedBrushes: function(widget_uri, sv) {
      var self = this;
      // We set all the brushes to their values, but this causes those brush
      // tabs to actually be selected.  Remember our last selected tab,
      // so we can go back to it.
      var lastSelected = self.lastSelectedStructure[widget_uri];
      if (widget_uri == 'stonehearth:build2:roof_widget') {
         self.selectBrush('wall', sv.data.wall_brush);
         self.selectBrush('column', sv.data.column_brush);
         self.selectBrush('roof', sv.data.roof_brush);
      } else if (widget_uri == 'stonehearth:build2:wall_widget' ||
            widget_uri == 'stonehearth:build2:perimeter_wall_widget') {
         self.selectBrush('wall', sv.data.brush);
         self.selectBrush('column', sv.data.column_brush);
      } else if (widget_uri == 'stonehearth:build2:room_widget') {
         self.selectBrush('floor', sv.data.floor_brush);
      } else if (widget_uri == 'stonehearth:build2:blocks_widget' ||
            widget_uri == 'stonehearth:build2:sub_blocks_widget') {
         self.selectBrush('voxel', sv.data.brush);
      } else if (widget_uri == 'stonehearth:build2:road_widget') {
         self.selectBrush('floor', sv.data.floor_brush);
      } else if (widget_uri == 'stonehearth:build2:stairs_widget') {
         self.selectBrush('stairs', sv.data.stairs_brush);
      }

      self.setStructureKind(lastSelected);
   },

   setSelected: function(selected) {
      var self = this;

      if (_.size(selected) == 1) {
         var uri = _.first(_.values(selected));

         if (uri == self.get('uri')) {
            self._onSelectionChange();
         } else {
            self.set('uri', uri);
         }
      }
   },

   setWidgets: function(widgetsKind) {
      var self = this;
      var available = self.structures.slice(0);
      var defaultKind = null;

      if (_.size(widgetsKind) == 0) {
         self.hide();
         return;
      }

      self.show();

      _.forEach(widgetsKind, function(__, uri) {
         if (uri == 'stonehearth:build2:entities:room_widget') {
            available = _.intersection(available, ['wall', 'column', 'floor']);
            defaultKind = 'wall';
         } else if (uri == 'stonehearth:build2:entities:wall_widget' ||
                    uri == 'stonehearth:build2:entities:perimeter_wall_widget') {
            available = _.intersection(available, ['wall', 'column']);
            defaultKind = 'wall';
         } else if (uri == 'stonehearth:build2:entities:blocks_widget' ||
                    uri == 'stonehearth:build2:entities:sub_blocks_widget') {
            available = _.intersection(available, ['voxel']);
            defaultKind = 'voxel';
         } else if (uri == 'stonehearth:build2:entities:road_widget') {
            available = _.intersection(available, ['floor']);
            defaultKind = 'floor';
         } else if (uri == 'stonehearth:build2:entities:roof_widget') {
            available = _.intersection(available, ['roof', 'wall', 'column']);
            defaultKind = 'roof';
         } else if (uri == 'stonehearth:build2:entities:stairs_widget') {
            available = _.intersection(available, ['stairs']);
            defaultKind = 'stairs';
         }
      });

      if (_.size(widgetsKind) == 1) {
         var lookup = _.first(_.keys(widgetsKind));
         var entitiesIdx = lookup.indexOf(':entities');
         var l = ':entities'.length;
         lookup = lookup.substring(0, entitiesIdx) + lookup.substring(entitiesIdx + l);

         self.lastSingleSelectedWidget = lookup;
         self.setStructureKind(self.lastSelectedStructure[self.lastSingleSelectedWidget]);
      } else if (defaultKind) {
         self.lastSingleSelectedWidget = null;
         self.setStructureKind(defaultKind);
      }

      self._setAvailableStructures(available);
   },

   _getMaterialImage(data) {
      if (data && data.builder_icon) {
         return data.builder_icon;
      } else if (data && data.icon) {
         return data.icon;
      }

      // TODO: should we have a default icon when there is none?
      return "";
   },

   _getHoverIcon(data) {
      var self = this;

      if (data && data.builder_icon_hover) {
         return data.builder_icon_hover;
      }

      return self._getMaterialImage(data);
   },

   _getTooltipKey(data) {
      if (data && data.tooltip) {
         return data.tooltip;
      } else if (data && data.name) {
         return data.name;
      }

      return "";
   },

   _buildResources: function() {
      var self = this;

      var resources = [];
      _.forEach(self._materials, function(__, key) {
         var data = App.resourceConstants.resources[key];
         var materialImage = self._getMaterialImage(data);
         var hoverImage = self._getHoverIcon(data);
         var tooltipKey = self._getTooltipKey(data);

         resources.push({
            material : key,
            style: 'background-image: url(' + materialImage + ')' + '; &:hover { background-image: url(' + hoverImage + ');}',
            title: data ? i18n.t(data.name) : "",
            tooltip: tooltipKey !== null ? i18n.t(tooltipKey) : "",
            ordinal: data ? data.ordinal : 99
         });

         resources.sort((a, b) => {
            if (a.ordinal != null && b.ordinal != null) {
               return a.ordinal - b.ordinal;
            }
            else if (a.ordinal != null) {
               return -1;
            }
            else if (b.ordinal != null) {
               return 1;
            }
         });
      });

      self.set('resources', resources);

      var el = self.$('#buildingResources');
      el.on('click', '.button', function() {
         var el2 = $(this);
         var key = $(this).data('material');
         self.setMaterial(key);
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_select_button'});
      });
   },

   _getStructureFromId: function(id) {
      var self = this;
      var result = '';
      _.forEach(self.tabKeyToId, function(tabid, key) {
         if (tabid == parseInt(id)) {
            result = key.split(':')[1];
         }
      });
      return result;
   },

   _getTabId: function(tabKey) {
      var self = this;
      if (self.tabKeyToId[tabKey] == null) {
         self.tabKeyToId[tabKey] = _.size(self.tabKeyToId);
      }

      return self.tabKeyToId[tabKey];
   },

   _hideStructureKinds: function() {
      var self = this;
      self.$('#structureContents').children().hide();
      self.$('#eyedropper').show();
   },

   _setAvailableStructures: function(structures) {
      var self = this;

      self._hideStructureKinds();

      if (_.isEmpty(structures)) {
         return;
      }

      self.$('#structureContents').children().each(function() {
         var el = $(this);
         if (_.indexOf(structures, el.attr('id')) >= 0) {
            el.show();
         }
      });

      if (_.indexOf(structures, self.structureKind) == -1) {
         self.setStructureKind(_.first(structures));
      }
   },

   setMaterial: function(material) {
      var self = this;
      self.material = material;
      self.$('#buildingResources').children().removeClass('selected');

      self.$('#buildingResources').children().each(function() {
         var el = $(this);

         if (el.data('material') == material) {
            el.addClass('selected');
         }
      });

      self._updateVisibleTab();
   },

   setActiveBrush: function(brush) {
      var self = this;

      self.setBrush(self.structureKind, brush);
   },

   _getFirstBrush: function(material, structureKind) {
      var self = this;

      var tabKey = material + ':' + structureKind;
      var tabId = self._getTabId(tabKey);
      return self.$('#' + tabId).children().first().data('brush');
   },

   selectBrush: function(structureKind, brush) {
      var self = this;
      // Clear the old selection.
      self.$('#brushes').children().each(function() {
         var id = $(this).attr('id');
         var sk = self._getStructureFromId(id);

         if (structureKind == sk) {
            $(this).children().removeClass('selected');

            $(this).children().each(function() {
               var el = $(this);
               if (el.data('brush') == brush) {
                  el.addClass('selected');
               }
            });
         }
      });

      if (brush) {
         self.selectedBrushes[structureKind] = brush;
      }

      self.setStructureKind(structureKind);

      if (brush) {
         self.setMaterial(self._brushToMaterial[brush]);
      }
   },

   setBrush: function(structureKind, brush) {
      var self = this;

      self.selectBrush(structureKind, brush);
      radiant.call_obj('stonehearth.building', 'set_brush_command', structureKind, brush);
   },

   getSelectedBrush: function(structureKind) {
      return self.selectedBrushes[structureKind];
   },

   setStructureKind: function(kind) {
      var self = this;
      self.structureKind = kind;
      self.$('#structureContents').children().removeClass('selected');
      var el = self.$('#structureContents').find('#' + kind);
      el.addClass('selected');

      // Select the material tab to which the previously-selected brush corresponds.
      self.setMaterial(self._brushToMaterial[self.selectedBrushes[kind]]);

      if (self.lastSingleSelectedWidget != null) {
         self.lastSelectedStructure[self.lastSingleSelectedWidget] = kind;
      }

      self._updateVisibleTab();
      self.$('#eyedropper').prop('disabled', kind == 'roof');

      if (kind == 'roof') {
         self.$('#eyedropper').addClass('disabled');
      } else {
         self.$('#eyedropper').removeClass('disabled');
      }
   },

   _updateVisibleTab: function() {
      var self = this;
      self.$('#brushes').children().each(function() {
         var el = $(this);
         el.hide();
      });

      var tabId = self._getTabId(self.material + ':' + self.structureKind);
      self.$('#' + tabId).show();
   },

   _buildBrushLists: function(tabs) {
      var self = this;
      _.forEach(tabs, function(kind) {
         self._hideStructureKinds();

         _.forEach(self._materials, function(e, material) {
            var realKind = kind;
            if (realKind == 'floor' || realKind == 'stairs') {
               realKind = 'voxel';
            }

            var tabKey = material + ':' + kind;
            var tabId = self._getTabId(tabKey);
            if (self.$('#' + tabId).length) {
               return;
            }

            var all_brushes = {};
            var colors = {};
            var patterns = {};

            if (self._buildBrushes[realKind][material] != null) {
               colors = self._buildBrushes[realKind][material].colors;
               patterns = self._buildBrushes[realKind][material].patterns;
            }

            $.extend(all_brushes,
               colors,
               patterns);

            if (kind != 'roof' && self._buildBrushes.always_available[material] != null) {
               $.extend(all_brushes,
                  self._buildBrushes.always_available[material].colors,
                  self._buildBrushes.always_available[material].patterns);
            }

            if (kind == 'floor' && self._buildBrushes.pattern[material] != null) {
               $.extend(all_brushes, self._buildBrushes.pattern[material].patterns);
            }

            var tabElementRoot = $('<div>').addClass('brushPalette').attr('id', tabId);
            self._buildBrushList(all_brushes, tabElementRoot);
            tabElementRoot.hide();

            tabElementRoot.on('click', '.button', function() {
               var el2 = $(this);
               var key = $(this).data('brush');
               self.setActiveBrush(key);
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_select_material'});
            });

            self.$('#brushes').append(tabElementRoot);
         });
      });
   },

   // ACE: added sorting of color brushes
   _buildBrushList: function(colors, elementRoot) {
      var self = this;

      var colorsArr = [];
      _.forEach(colors, function(data, name) {
         data.name = name;
         data.title = i18n.t(data.display_name);
         colorsArr.push(data);
      });

      colorsArr.sort((a, b) => {
         if (a.ordinal != null && b.ordinal != null) {
            return a.ordinal - b.ordinal;
         }
         else if (a.ordinal != null) {
            return -1;
         }
         else if (b.ordinal != null) {
            return 1;
         }
         else {
            return ('' + a.title).localeCompare(b.title);
         }
      });

      _.forEach(colorsArr, function(data) {
         var name = data.name;
         var brush = $('<div>')
                     .addClass('brush')
                     .addClass('button')
                     .data('brush', name.toLowerCase())
                     .attr('title', data.title)
                     .attr('tooltip', i18n.t(data.display_name));
         if (data.icon) {
            brush = brush.css({ 'background-image' : 'url(' + data.icon + ')' });
         } else if (name) {
            brush = brush.css({ 'background-color' : name });
         }
         brush.append('<div class=selectBox />');

         elementRoot.append(brush);
      });
   },

   showEditor: function() {
      this._super();
   },

   actions: {
      changeStructure: function(structureKind) {
         var self = this;

         self.setStructureKind(structureKind);
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_select_button'});
      },

      pickColor: function() {
         var self = this;

         var lastTool = self.get('parentView').getActiveTool();

         radiant.call_obj('stonehearth.building', 'do_tool_command', 'pick_color_command', true)
            .progress(function(v) {
               self.setMaterial(v.material);
               var hexstr = v.tag.toString(16);
               while (hexstr.length < 6) {
                  hexstr = '0' + hexstr;
               }
               hexstr = hexstr.substring(4, 6) + hexstr.substring(2, 4) + hexstr.substring(0, 2);
               self.setActiveBrush('#' + hexstr);
            })
            .always(function() {
               self.get('parentView').send('restoreTool', lastTool);
            });
      }
   }
});
