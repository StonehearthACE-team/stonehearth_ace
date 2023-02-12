App.StonehearthSelectSettlementView = App.View.extend({
   templateName: 'stonehearthSelectSettlement',
   i18nNamespace: 'stonehearth',

   classNames: ['flex', 'fullScreen', 'selectSettlementBackground'],

   // Game options (such as peaceful mode, etc.)
   options: {},
   analytics: {},

   init: function() {
      this._super();
      var self = this;
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      var biome_uri = self.get('options.biome_src');
      var kingdom_uri = self.get('options.starting_kingdom');
      self.$('#selectSettlement').addClass(biome_uri);
      self.$('#selectSettlement').addClass(kingdom_uri);
      self.$('.bullet').addClass(biome_uri);

      self._newGame(self._generate_seed(), function (e) {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:paper_menu'} );
         self.$('#map').stonehearthMap({
            mapGrid: e.map,
            mapInfo: e.map_info,

            click: function(cellX, cellY) {
               self._chooseLocation(cellX, cellY);
            },

            hover: function(cellX, cellY) {
               var map = $('#map').stonehearthMap('getMap');
               var cell = map[cellY] && map[cellY][cellX];
               if (cell) {
                  self._updateScroll(cell);
               }
            }
         });
      });

      $('body').on( 'click', '#selectSettlementButton', function() {
         self._selectSettlement(self._selectedX, self._selectedY);
      });

      $('body').on( 'click', '#clearSelectionButton', function() {
         self._clearSelection();
      });

      self.$("#regenerateButton").click(function() {
         if (self.$("#regenerateButton").hasClass('disabled')) {
            return;
         }

         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:reroll'} );
         self._clearSelection();
         self.$('#map').hide();
         self.$('#map').stonehearthMap('suspend');

         self._newGame(self._generate_seed(), function(e) {
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:paper_menu'} );
            self.$('#map').show();
            self.$('#map').stonehearthMap('setMap', e.map, e.map_info);
            self.$('#map').stonehearthMap('resume');
         });
      });

      // World Seed
      new StonehearthInputHelper(this.$('#worldSeedInput'), function (value) {
            var worldSeed = self.get('world_seed');
            if (self.$("#regenerateButton").hasClass('disabled')) {
               self.$('#worldSeedInput').val(worldSeed);
               return;
            }
            var seed = parseInt(value);
            if (isNaN(seed)) {
               self.$('#worldSeedInput').val(worldSeed);
               return;
            }

            if (seed != worldSeed) {
               self.$('#map').hide();
               self.$('#map').stonehearthMap('suspend');
               self._newGame(seed ,function(e) {
                  self.$('#map').show();
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:paper_menu'} );
                  self.$('#map').stonehearthMap('setMap', e.map, e.map_info);
                  self.$('#map').stonehearthMap('resume');
               });
            }
         });

      $(document).on('keydown', this._clearSelectionKeyHandler);

      self._animateLoading();
   },

   _loadSeasons: function () {
      var self = this;
      var biome_uri = self.get('options.biome_src');
      if (biome_uri) {
         self.trace = radiant.trace(biome_uri)
            .progress(function (biome) {
               self.set('seasons', radiant.map_to_array(biome.seasons, function(k, b) { b.id = k; }));

               Ember.run.scheduleOnce('afterRender', this, function () {
                  var seasonDivs = self.$('[data-season-id]');
                  if (seasonDivs) {
                     seasonDivs.each(function () {
                        var $el = $(this);
                        var id = $el.attr('data-season-id');
                        var description = biome.seasons[id].description;
                        if (description) {
                           var tooltip = $(App.tooltipHelper.createTooltip(null, i18n.t(description, {escapeHTML: true})));
                           $el.tooltipster({ content: tooltip, position: 'bottom' });
                        }
                     });
                     if (biome.default_starting_season) {
                        self.$('[data-season-id="' + biome.default_starting_season + '"] input').attr('checked', true);
                     } else {
                        self.$('[data-season-id] input').first().attr('checked', true);
                     }
                  }
               });
            })
      }
   }.observes('options.biome_src'),

   seasonRows: function () {
      var self = this;
      var i = 0;
      var result = [];
      radiant.each(self.get('seasons'), function (_, season) {
         var row = Math.floor(i / 2);
         if (!result[row]) result[row] = [];
         result[row].push(season);
         ++i;
      });
      return result;
   }.property('seasons'),

   destroy: function() {
      $(document).off('keydown', this._clearSelectionKeyHandler);
      if (this._loadingAnimationInterval) {
         clearInterval(this._loadingAnimationInterval);
         this._loadingAnimationInterval = null;
      }
      this._super();
   },

   _animateLoading: function() {
      var self = this;
      var loadingElement = self.$('#loadingPeriods');

      var periodsCount = 0;
      var currentPeriods = '';
      self._loadingAnimationInterval = setInterval(function() {
         loadingElement.html(currentPeriods);

         periodsCount++;
         if (periodsCount >= 4) {
            periodsCount = 0;
            currentPeriods = '';
         } else {
            currentPeriods = currentPeriods + '.';
         }

      }, 250);

   },

   _chooseLocation: function(cellX, cellY) {
      var self = this;

      self._selectedX = cellX;
      self._selectedY = cellY;

      self.$('#map').stonehearthMap('suspend');

      // Must show before setting position. jQueryUI does not support positioning of hidden elements.
      self.$('#selectSettlementPin').show();
      self.$('#selectSettlementPin').position({
         my: 'left+' + 12 * cellX + ' top+' + 12 * cellY,
         at: 'left top',
         of: self.$('#map'),
      })

      var tipContent = '<div id="selectSettlementTooltip">';
      tipContent += '<button id="selectSettlementButton" class="flat">' + i18n.t('stonehearth:ui.shell.select_settlement.settle_at_this_location') + '</button><br>';
      tipContent += '<button id="clearSelectionButton" class="flat">' + i18n.t('stonehearth:ui.shell.select_settlement.clear_selection') + '</button>';
      tipContent += '</div>'

      self.$('#selectSettlementPin').tooltipster({
         autoClose: false,
         interactive: true,
         content:  $(tipContent)
      });

      self.$('#selectSettlementPin').tooltipster('show');
   },

   _newGame: function(seed, fn) {
      var self = this;
      self.set('world_seed', seed);

      self.$("#regenerateButton").addClass('disabled');
      self.$('#worldSeedInput').attr('disabled', 'disabled');

      radiant.call_obj('stonehearth.game_creation', 'new_game_command', 12, 8, seed, self.options, self.analytics)
         .done(function(e) {
            self._map_info = e.map_info;
            fn(e);
         })
         .fail(function(e) {
            console.error('new_game failed:', e);
         })
         .always(function() {
            self.$("#regenerateButton").removeClass('disabled');
            self.$('#worldSeedInput').removeAttr('disabled');
         });
   },

   _generate_seed: function() {
      // unsigned ints are marshalling across as signed ints to lua
      //var MAX_UINT32 = 4294967295;
      var MAX_INT32 = 2147483647;
      var seed = Math.floor(Math.random() * (MAX_INT32+1));
      return seed;
   },

   _updateScroll: function(cell) {
      var self = this;
      var terrainType = '';
      var vegetationDescription = '';
      var wildlifeDescription = '';

      if (cell != null) {
         self.$('#scroll').show();

         if (self._map_info && self._map_info.custom_name_map && self._map_info.custom_name_map[cell.terrain_code]) {
            terrainType = i18n.t(self._map_info.custom_name_map[cell.terrain_code]);
         } else {
            terrainType = i18n.t('stonehearth:ui.shell.select_settlement.terrain_codes.' + cell.terrain_code);
         }

         vegetationDescription = cell.vegetation_density;
         wildlifeDescription = cell.wildlife_density;
         mineralDescription = cell.mineral_density;

         if (cell.terrain_code != this._prevTerrainCode) {
            var portrait = 'url(/stonehearth/ui/shell/select_settlement/images/' + cell.terrain_code + '.png)';
            self.$('#terrainType').html(terrainType);
            this._prevTerrainCode = cell.terrain_code;
         }

         self._updateTileRatings(self.$('#vegetation'), cell.vegetation_density);
         self._updateTileRatings(self.$('#wildlife'), cell.wildlife_density);
         self._updateTileRatings(self.$('#minerals'), cell.mineral_density);

         /*
         self.$('#vegetation')
            .removeAttr('class')
            .addClass('level' + cell.vegetation_density)
            .html(vegetationDescription);

         self.$('#wildlife')
            .removeAttr('class')
            .addClass('level' + cell.wildlife_density)
            .html(wildlifeDescription);

         self.$('#minerals')
            .removeAttr('class')
            .addClass('level' + cell.mineral_density)
            .html(mineralDescription);
         */
      } else {
         self.$('#scroll').hide();
      }
   },

   _updateTileRatings: function(el, rating) {
      el.find('.bullet')
         .removeClass('full');

      for(var i = 1; i < rating + 1; i++) {
         el.find('.' + i).addClass('full');
      }
   },

   _clearSelection: function() {
      var self = this;

      try {
         self.$('#selectSettlementPin').tooltipster('destroy');
         self.$('#selectSettlementPin').hide();
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:menu_closed'} );
      } catch(e) {
      }

      self.$('#map').stonehearthMap('clearCrosshairs');
      self._updateScroll(null);

      if (self.$('#map').stonehearthMap('suspended')) {
         self.$('#map').stonehearthMap('resume');
      }
   },

   _clearSelectionKeyHandler: function(e) {
      var self = this;

      var escape_key_code = 27;

      if (e.keyCode == escape_key_code) {
         $('#clearSelectionButton').click();
      }
   },

   _selectSettlement: function(cellX, cellY) {
      var self = this;

      radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:embark'} );
      radiant.call_obj('stonehearth.game_creation', 'generate_start_location_command', cellX, cellY, self._map_info)
         .fail(function(e) {
            console.error('generate_start_location_command failed:', e);
         });

      var chosenSeason = self.$('[data-season-id] input:checked');
      if (chosenSeason && chosenSeason.length) {
         var transitionDays = parseInt(App.constants.seasons.TRANSITION_LENGTH) || 0;  // HACK: assumes this is in the "#d" form.
         var seasonStartDay = parseInt(chosenSeason.attr('data-season-start-day'));
         radiant.call('stonehearth:set_start_day', seasonStartDay + transitionDays);
      }

      App.navigate('shell/loading');
      self.destroy();
   },

   actions: {
      quitToMainMenu: function() {
         App.stonehearthClient.quitToMainMenu('shellView');
      }
   },
});
