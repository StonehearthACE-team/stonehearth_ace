App.AceBuildFenceModeView = App.View.extend({
   templateName: 'fenceMode',
   closeOnEsc: false,
   modal: false,

   _shownFirstTime: false,

   dismiss: function() {
      this.hide();
   },

   show: function() {
      var self = this;
      var isVisible = self.visible();
      self._super();
      
      // only perform initialization stuff if the view wasn't already visible
      if (!isVisible) {
         if (!self._shownFirstTime) {
            self._shownFirstTime = true;
            self._loadSegments();
            self._loadPresets();
            self._loadConfigSegments();
         }
         else {
            self.buildFence();
         }
      }
      else {
         self.buildFence();
      }
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      self._fenceData = stonehearth_ace.getFenceModeData();
      self._craftable = {};

      var segmentsDiv = self.$('#fenceSegmentsDiv');
      segmentsDiv.on('mousemove', function(e) {
         var segments = self.get('segments') || [];
         if (self.$('#presetSelection').is(':visible') || self.$('#segmentSelection').is(':visible') || segments.length > 20) {
            self.set('canAddSegment', false);
            return;
         }

         // find the appropriate insert index based on location
         var x = e.pageX - segmentsDiv.offset().left;
         //var y = segmentsDiv.height() - (e.pageY - segmentsDiv.offset().top);
         var index = Math.floor((x - 5) / 75 + 0.5);
         self._insertIndex = index;
         var btn = self.$('#addSegmentBtn');
         var left = index * 75 - btn.width() / 2 + 5;
         btn.css('left', left);
         self.set('canAddSegment', Math.abs(x - left) < 50);
      })
      .on('mouseleave', function(e) {
         self.set('canAddSegment', false);
      });

      self.$().on('contextmenu', '.fenceSegmentContainer', function() {
         var index = $(this).find('.toggleSegmentBtn').data('index');
         var segments = self.get('segments');
         var newSegments = [];
         for (var i = 0; i < segments.length; i++) {
            if (i != index) {
               var newSegment = self._getProperSegment(segments[i].uri, segments[i].enabled);
               newSegments.push(newSegment);
            }
         }
         for (var i = newSegments.length; i < 2; i++) {
            var newSegment = self._getProperSegment(newSegments[i - 1].uri, false);
            newSegments.push(newSegment);
         }
         self._setCurrentSegments(newSegments);
         self._updateSegmentsConfig();
         self.$('#segmentSelection').hide();

         return false;
      });
      
      self.$().on('click', '.presetPreview', function(e) {
         if (self.get('inLoadMode')) {
            $(this.parentElement).find('.loadPreset').click();
         }
         else if (self.get('inSaveMode')) {
            $(this.parentElement).find('.savePreset').click();
         }
      })

      var presetSearch = self.$('#presetSearch');
      presetSearch.keydown(function(e) {
         if (e.keyCode === 27) {
            self._togglePresetsVisibility(false);
            return false;
         }
      })
      .keyup(function(e) {
         var text = presetSearch.val();
         if (e.keyCode != 13 && e.keyCode != 27) {
            // filter the results by the text
            var lowerText = text.toLowerCase();
            var customNameExists = false;
            self.$('.presetRow').each(function() {
               var thisRow = $(this);
               var name = thisRow.data('name');
               var isDefault = thisRow.hasClass('default');
               var preset = self._getPreset(name, isDefault);
               if (lowerText.length < 1 || preset.title.toLowerCase().includes(lowerText)) {
                  thisRow.show();
               }
               else {
                  thisRow.hide();
               }
               if (!isDefault && name == text) {
                  customNameExists = true;
               }
            });
            
            self.set('saveAllowed', !customNameExists);
         }
         else if (e.keyCode == 13 && text.length > 0) {
            var existingPreset = self._customPresets[text];
            if (self.get('inSaveMode')) {
               self._showSaveOverrideConfirmation(text);
            }
            else if (self.get('inLoadMode') && existingPreset) {
               self._loadPreset(existingPreset);
            }
         }
      });

      App.tooltipHelper.createDynamicTooltip(presetSearch , function () {
         var mode = self.get('inSaveMode') ? 'save_mode' : 'load_mode';
         return i18n.t('stonehearth_ace:ui.game.fence_mode.preset_filter.' + mode + '.description');
      });

      App.jobController.addChangeCallback('fence_mode', function() {
         self._updateAvailability();
      }, true);

      App.tooltipHelper.attachTooltipster(self.$('#showLoadPreset'),
         $(App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.show_load.title'),
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.show_load.description')))
      );
      App.tooltipHelper.attachTooltipster(self.$('#showSavePreset'),
         $(App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.show_save.title'),
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.show_save.description')))
      );
      App.tooltipHelper.attachTooltipster(self.$('#reverseSegments'),
         $(App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.reverse_segments.title'),
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.reverse_segments.description')))
      );

      App.guiHelper.createDynamicTooltip(self.$('#fenceSegmentsDiv'), '.toggleSegmentBtn', function($el) {
         var enabledStr = $el.hasClass('enabled') ? 'segment_enabled' : 'segment_disabled';
         return $(App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.' + enabledStr + '.title'),
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.' + enabledStr + '.description')));
      }, {delay: 500, position: 'bottom'});

      App.guiHelper.createDynamicTooltip(self.$('#fenceSegmentsDiv'), '.buildFromSegmentBtn', function() {
         return $(App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.build_from_segment.title'),
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.build_from_segment.description')));
      }, {delay: 500});

      App.guiHelper.createDynamicTooltip(self.$('#fenceSegmentsDiv'), '.buildSegmentBtn', function() {
         return $(App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.build_segment.title'),
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.build_segment.description')));
      }, {delay: 500});
   },

   willDestroyElement: function() {
      App.jobController.removeChangeCallback('fence_mode');
      App.guiHelper.removeDynamicTooltip(this.$('#fenceSegmentsDiv'), '.toggleSegmentBtn');
      App.guiHelper.removeDynamicTooltip(this.$('#fenceSegmentsDiv'), '.buildFromSegmentBtn');
      App.guiHelper.removeDynamicTooltip(this.$('#fenceSegmentsDiv'), '.buildSegmentBtn');
      this.$().find('.tooltipstered').tooltipster('destroy');
      this.$('#presetSearch').off('keydown').off('keyup');
      this.$().off('click', '.presetRow');
      this._super();
   },

   _loadSegments: function() {
      var self = this;
      var segments = [];
      self._segments = {};

      var allFences = App.catalog.getFilteredCatalogData('fence', function(uri, catalogData) {
         return catalogData.fence_length != null && uri[0] != '/';
      });
      radiant.each(allFences, function(uri, catalogData) {
         var segment = {
            uri: uri,
            length: catalogData.fence_length,
            icon: catalogData.icon,
            display_name: catalogData.display_name,
            description: catalogData.description
         };
         self._segments[uri] = segment;
         segments.push(segment);
      });

      // maybe we'll divide them into categories at some point; for now, just sort them by uri and lump them all together
      segments.sort((a, b) => a.uri.localeCompare(b.uri));
      self.set('allSegments', segments);
      self._updateAvailability();
      Ember.run.scheduleOnce('afterRender', self, '_updateAllSegmentTooltips');
   },

   _loadPresets: function() {
      var self = this;
      // first add the default presets; then add the custom presets
      var presets = [];
      self._defaultPresets = {};
      self._customPresets = {};

      radiant.each(self._fenceData.default_presets, function(name, segments) {
         var preset = self._createPresetObj(name, segments, true);
         presets.push(preset);
         self._defaultPresets[name] = preset;
      });

      radiant.each(self._fenceData.custom_presets, function(name, segments) {
         var preset = self._createPresetObj(name, segments);
         presets.push(preset);
         self._customPresets[name] = preset;
      });

      self.set('presets', presets);
      self.$('#presetSearch').val('');
      Ember.run.scheduleOnce('afterRender', self, '_updatePresetTooltips');
   },

   _createPresetObj: function(name, segments, isDefault) {
      var self = this;
      var preset = {
         name: name,
         segments: self._getProperSegments(segments),
         default: isDefault,
         title: isDefault ? i18n.t('stonehearth_ace:ui.game.fence_mode.presets.' + name) : name
      }
      return preset;
   },

   _getProperSegments: function(segments) {
      var self = this;
      var presetSegments = [];
      radiant.each(segments, function(_, segment) {
         var result = self._getProperSegment(segment.uri, segment.enabled);
         if (result) {
            presetSegments.push(result);
         }
      });
      return presetSegments;
   },

   _getProperSegment: function(uri, enabled) {
      var self = this;
      var lookup = self._segments[uri];
      if (lookup) {
         var presetSegment = radiant.shallow_copy(lookup);
         presetSegment.enabled = enabled;
         return presetSegment;
      }
   },

   _loadConfigSegments: function() {
      var self = this;
      var segments = self._fenceData.selected_segments;
      if (segments) {
         self._setCurrentSegments(self._getProperSegments(segments));
      }
      else {
         self._loadPreset({default: true, name: 'wood1'});
      }
   },

   _updateAvailability: function() {
      // go through all recipes and update availability of all fence segment crafting
      var self = this;
      if (!self._segments) {
         return;
      }
      // var allSegments = self.get('allSegments');
      // if (!allSegments) {
      //    return;
      // }

      var jobData = App.jobController.getJobControllerData();
      if (!jobData || !jobData.jobs) {
         return;
      }

      _.forEach(jobData.jobs, function(jobControllerInfo, jobUri) {
         if (!jobControllerInfo.recipe_list) {
            return;
         }

         var jobInfo = App.jobConstants[jobUri];
         var jobIcon;
         if (jobInfo) {
            jobIcon = jobInfo.description.icon;
         }

         var highestLevel = jobControllerInfo.num_members > 0 && jobControllerInfo.highest_level || 0;

         _.forEach(jobControllerInfo.recipe_list, function(category) {
            _.forEach(category.recipes, function(recipe_info, recipe_key) {
               var recipe = recipe_info.recipe;
               var product_uri = recipe.product_uri;

               var segment = self._segments[product_uri];
               if (!segment) {
                  // if it's not one of our segments, we don't care about it
                  return;
               }

               var available = false;
               var crafterRequirement = null;
               if (recipe.manual_unlock && !jobControllerInfo.manually_unlocked[recipe.recipe_key]) {
                  // if it's locked, don't show that it's craftable
               }
               else {
                  // show unmet requirement
                  var level = Math.max(1, recipe.level_requirement || 1);
                  crafterRequirement = {
                     jobUri: jobUri,
                     jobIcon: jobIcon,
                     level: level,
                     met: highestLevel >= level,
                  };

                  if (crafterRequirement.met) {
                     // it's actually craftable, show it as available
                     available = true;
                  }
               }

               Ember.set(segment, 'crafterRequirement', crafterRequirement);
               Ember.set(segment, 'available', available);
            });
         });
      });
   },

   _updateAllSegmentTooltips: function() {
      // this function is run only at the beginning to set up dynamic tooltips for all the possible segments in the palette window
      var self = this;
      var segmentDivs = self.$('.segmentDiv');
      if (segmentDivs) {
         segmentDivs.each(function() {
            self._createSegmentTooltip($(this), 250);
         });
      }
   },

   _updateSegmentTooltips: function() {
      var self = this;
      var fenceSegmentBtns = self.$('.fenceSegmentBtn');
      if (fenceSegmentBtns) {
         fenceSegmentBtns.each(function() {
            self._createSegmentTooltip($(this), 250);
         });
         // self.$('.toggleSegmentBtn').each(function() {
         //    var $el = $(this);
         //    App.tooltipHelper.createDynamicTooltip($el , function () {
         //       var enabledStr = $el.hasClass('enabled') ? 'segment_enabled' : 'segment_disabled';
         //       return $(App.tooltipHelper.createTooltip(
         //          i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.' + enabledStr + '.title'),
         //          i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.' + enabledStr + '.description')));
         //    }, {delay: 250, position: 'bottom'});
         // });
      }
   },

   _createSegmentTooltip: function($el, delay) {
      var self = this;
      var uri = $el.data('uri');
      var segment = self._segments[uri];
      App.tooltipHelper.createDynamicTooltip($el, function () {
         var crafterRequirement = self._getCrafterRequirementText(segment.crafterRequirement);
         return $(App.tooltipHelper.createTooltip(i18n.t(segment.display_name), i18n.t(segment.description), crafterRequirement));
      }, {delay: delay});
   },

   _getCrafterRequirementText: function(crafterRequirement) {
      // show crafter icon and level required (if it can be crafted), with formatting based on meeting requirements
      var self = this;
      if (crafterRequirement) {
         return `<span class="requirement${crafterRequirement.met ? ' requirementMet' : ''}"><img class="jobIcon" src="${crafterRequirement.jobIcon}"/>` +
               `${i18n.t('stonehearth_ace:ui.game.fence_mode.level_requirement', crafterRequirement)}</span>`;;
      }
      
      return null;
   },

   _getPresetCrafterRequirementText: function(preset) {
      // go through each segment and combine the crafter requirements
      var self = this;
      var requirements = {};
      preset.segments.forEach(seg => {
         var segment = self._segments[seg.uri];
         if (segment.crafterRequirement) {
            var jobUri = segment.crafterRequirement.jobUri;
            var lvl = requirements[jobUri] && requirements[jobUri].level || 1;
            var met = requirements[jobUri] ? requirements[jobUri].met : true;
            requirements[jobUri] = {
               jobIcon: segment.crafterRequirement.jobIcon,
               level: Math.max(lvl, segment.crafterRequirement.level),
               met: met && segment.crafterRequirement.met,
            }
         }
      });

      var requirementText = '';
      var isMet = true;
      radiant.each(requirements, function(jobUri, requirement) {
         if (requirementText.length > 0) {
            requirementText += ' ';
         }
         requirementText += self._getCrafterRequirementText(requirement);
         isMet = isMet && requirement.met;
      });

      if (requirementText.length > 0)
      {
         return `<div class="requirementText${isMet ? ' requirementMet' : ''}">${i18n.t('stonehearth_ace:ui.game.fence_mode.crafter_requirement')}${requirementText}</div>`;
      }
   },

   _updatePresetTooltips: function() {
      var self = this;
      var presetRows = self.$('.presetRow');
      if (presetRows) {
         presetRows.each(function() {
            var name = $(this).data('name');
            var isDefault = $(this).hasClass('default');
            var preset = self._getPreset(name, isDefault);
            App.tooltipHelper.createDynamicTooltip($(this).find('.presetPreview'), function () {
               // maybe work in the crafting requirements to this tooltip (e.g., 3/4 craftable, requires [Mason] Lvl 2)
               var requirementText = self._getPresetCrafterRequirementText(preset);
               return $(App.tooltipHelper.createTooltip(preset.title, requirementText));
            }, {position: 'right', offsetX: 60});

            // $(this).find('.presetSegmentImg').each(function() {
            //    self._createSegmentTooltip(self, $(this));
            // });

            $(this).find('.loadPreset').each(function() {
               App.tooltipHelper.createDynamicTooltip($(this), function () {
                  return $(App.tooltipHelper.createTooltip(i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.load_preset.title')));
               });
            });
            $(this).find('.savePreset').each(function() {
               App.tooltipHelper.createDynamicTooltip($(this), function () {
                  return $(App.tooltipHelper.createTooltip(
                     i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.save_preset.title'),
                     i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.save_preset.description')));
               });
            });
            $(this).find('.deletePreset').each(function() {
               App.tooltipHelper.createDynamicTooltip($(this), function () {
                  return $(App.tooltipHelper.createTooltip(
                     i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.delete_preset.title'),
                     i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.delete_preset.description')));
               });
            });
         });
      }
   },

   _togglePresetsVisibility: function(mode) {
      var self = this;
      var presets = self.$('#presetSelection');
      var visibility = false;
      if (mode) {
         visibility = !self.get(mode);
         if (!visibility) {
            mode = null;
         }
      }
      if (!visibility) {
         self._hidePresets();
         if (!mode) {
            // if the user simply closed the presets window
            self.buildFence();
         }
      }
      else {
         self._hideSegmentSelection();
         self._loadPresets();
         self.set('inLoadMode', mode == 'inLoadMode');
         self.set('inSaveMode', mode == 'inSaveMode');
         presets.show();
         //self.set('canAddSegment', false);
         App.stonehearthClient.deactivateAllTools();
      }
   },

   _hidePresets: function() {
      var self = this;
      self.$('#presetSelection').hide();
      self.set('inLoadMode', false);
      self.set('inSaveMode', false);
   },

   _hideSegmentSelection: function() {
      var self = this;
      self._activeSegment = null;
      self.$('#segmentSelection').hide();
      self.$('.fenceSegmentBtn').removeClass('selected');
   },

   _loadPreset: function(preset) {
      var self = this;
      var realPreset = self._getPreset(preset.name, preset.default);

      if (realPreset) {
         // slice(0) clones the array
         self._setCurrentSegments(realPreset.segments.slice(0));
         self._updateSegmentsConfig();
         self._togglePresetsVisibility(false);
      }
   },

   _getPreset: function(name, isDefault) {
      var self = this;
      if (isDefault) {
         return self._defaultPresets[name];
      }
      else {
         return self._customPresets[name];
      }
   },

   _setCurrentSegments: function(segments) {
      var self = this;
      self.set('segments', segments);
      Ember.run.scheduleOnce('afterRender', self, '_updateSegmentTooltips');
      self.buildFence();
   },

   buildFence: function(fromSegment, internalRecall) {
      var self = this;

      var curSegments = self.get('segments');
      if (!curSegments) {
         App.stonehearthClient.deactivateAllTools();
         return;
      }

      // if fromSegment is specified, shift the segment array so it starts with that one
      if (fromSegment) {
         var index = curSegments.indexOf(fromSegment);
         if (index > 0) {
            curSegments = curSegments.slice(index).concat(curSegments.slice(0, index));
         }
      }

      var fencePieces = [];
      curSegments.forEach(segment => {
         if (segment.enabled) {
            fencePieces.push(segment.uri);
         }
      });

      if (fencePieces.length < 1) {
         App.stonehearthClient.deactivateAllTools();
         return;
      }

      var curTip = App.stonehearthClient._currentTip;
      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.build_menu.items.build_fence.tip_title', 'stonehearth_ace:ui.game.menu.build_menu.items.build_fence.tip_description',
         {i18n: true});
      self._recallingTool = !internalRecall && tip == curTip;

      var toolFn;
      toolFn = function() {
         return radiant.call('stonehearth_ace:choose_fence_location_command', fencePieces)
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               self.buildFence(fromSegment, true);
            })
            .fail(function(response) {
               if (!self._recallingTool) {
                  App.stonehearthClient.hideTip(tip);
               }
               self._recallingTool = false;
            });
      };

      return App.stonehearthClient._callTool('buildFence', toolFn);
   },

   buildSegment: function(uri) {
      App.stonehearthClient.craftAndPlaceItemType(uri, 'fence');
   },

   _updateSegmentsConfig: function() {
      var self = this;
      stonehearth_ace.updateFenceModeSettings(self._getSegmentsConfigToSave());
   },

   _getSegmentsConfigToSave: function() {
      var self = this;
      var segments = self.get('segments');
      var toSave = [];
      segments.forEach(segment => {
         toSave.push({
            uri: segment.uri,
            enabled: segment.enabled
         })
      });
      return toSave;
   },

   _updatePresetsConfig: function() {
      var self = this;
      stonehearth_ace.updateFenceModeSettings(null, self._fenceData.custom_presets);
   },

   _showSegmentSelection: function(segment) {
      var self = this;
      if (self._activeSegment == segment) {
         self._hideSegmentSelection();
         self.buildFence();
      }
      else {
         self._hidePresets();
         self._activeSegment = segment;
         self._selectSegmentInSelectionWindow(segment.uri);
         var index = Math.max(0, self.get('segments').indexOf(segment));
         self.$('#segmentSelection').css('left', index * 75 + 'px');
         self.$('#segmentSelection').show();

         self.$('.fenceSegmentBtn').removeClass('selected');
         // have to do this after render because we might be inserting a new segment
         Ember.run.scheduleOnce('afterRender', self, function() {
            var fenceSegmentBtns = self.$('.fenceSegmentBtn');
            if (fenceSegmentBtns) {
               $(fenceSegmentBtns.get(index)).addClass('selected');
            }
         });

         self.set('canAddSegment', false);
         App.stonehearthClient.deactivateAllTools();
      }
   },

   _selectSegmentInSelectionWindow: function(uri) {
      var self = this;
      var allSegments = self.$('#segmentSelection');
      allSegments.find('.segmentDiv').removeClass('selected');
      allSegments.find('[data-uri="' + uri + '"]').addClass('selected');
   },

   _showSaveOverrideConfirmation: function(name) {
      // TODO add save override confirmation dialog
      // for now just do it! who cares, what are they gonna do about it?!
      var self = this;
      if (!name || name.length < 1) {
         return;
      }
      if (self._customPresets[name]) {
         // do confirmation and return if canceled
      }
      self._saveCustomPreset(name);
   },

   _saveCustomPreset: function(name) {
      var self = this;
      self._fenceData.custom_presets[name] = self._getSegmentsConfigToSave();
      self._updatePresetsConfig();
      self._loadPresets();
      self._togglePresetsVisibility(false);
   },

   _showDeletePresetConfirmation: function(name) {
      // TODO add save override confirmation dialog
      // for now just do it! who cares, what are they gonna do about it?!
      var self = this;
      self._deleteCustomPreset(name);
   },

   _deleteCustomPreset: function(name) {
      var self = this;
      delete self._fenceData.custom_presets[name];
      self._updatePresetsConfig();
      self._loadPresets();
   },

   actions: {
      selectSegment: function(segment) {
         var self = this;
         self._showSegmentSelection(segment);
      },

      setSegment: function(newSegmentUri) {
         var self = this;
         self._selectSegmentInSelectionWindow(newSegmentUri);
         if (self._activeSegment) {
            var segments = self.get('segments');
            var newSegments = [];
            var index = segments.indexOf(self._activeSegment);
            for (var i = 0; i < segments.length; i++) {
               var newSegment = self._getProperSegment(index == i ? newSegmentUri : segments[i].uri, index == i || segments[i].enabled);
               newSegments.push(newSegment);
            }
            self._setCurrentSegments(newSegments);
            self._updateSegmentsConfig();
            self._activeSegment = null;
         }
         self._hideSegmentSelection();
      },

      insertSegment: function() {
         var self = this;
         if (self._insertIndex != null) {
            var segments = self.get('segments');
            var newSegments = [];
            for (var i = 0; i < segments.length; i++) {
               var newSegment = self._getProperSegment(segments[i].uri, segments[i].enabled);
               newSegments.push(newSegment);
            }
            var prevSegment = segments[Math.max(0, self._insertIndex - 1)];
            newSegments.splice(self._insertIndex, 0, self._getProperSegment(prevSegment.uri, true));
            self._setCurrentSegments(newSegments);
            self._updateSegmentsConfig();
            self.set('canAddSegment', false);
            self._showSegmentSelection(self.get('segments')[self._insertIndex]);
         }
      },

      toggleSegment: function(segment) {
         var self = this;
         if (segment) {
            Ember.set(segment, 'enabled', !segment.enabled);
            self._updateSegmentsConfig();
            self.buildFence();
         }
      },

      buildSegment: function(segment) {
         var self = this;
         if (segment) {
            App.stonehearthClient.deactivateAllTools();
            self.buildSegment(segment.uri);
         }
      },

      buildFromSegment: function(segment) {
         var self = this;
         if (segment) {
            App.stonehearthClient.deactivateAllTools();
            self.buildFence(segment);
         }
      },

      reverseSegments: function() {
         var self = this;
         var segments = self.get('segments');
         App.stonehearthClient.deactivateAllTools();
         segments.reverseObjects();
         self._setCurrentSegments(segments);
         self._updateSegmentsConfig();
      },

      showLoadPreset: function() {
         var self = this;
         self._togglePresetsVisibility('inLoadMode');
      },

      showSavePreset: function() {
         var self = this;
         self._togglePresetsVisibility('inSaveMode');
      },

      loadPreset: function(preset) {
         var self = this;
         self._loadPreset(preset);
      },

      savePreset: function(preset) {
         var self = this;
         self._showSaveOverrideConfirmation(preset && preset.name);
      },

      saveCurrentPreset: function() {
         var self = this;
         self._showSaveOverrideConfirmation(self.get('saveAllowed') && self.$('#presetSearch').val());
      },

      deletePreset: function(preset) {
         var self = this;
         self._showDeletePresetConfirmation(preset.name);
      }
   }
});
