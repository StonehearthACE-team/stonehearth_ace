App.StonehearthLoadoutScreenView = App.View.extend({

   templateName: 'stonehearthLoadoutScreen',
   i18nNamespace: 'stonehearth',
   classNames: ['flex', 'fullScreen', 'newGameFlowBackground'],
   _options: {},
   _analytics: {},

   init: function() {
      this._super();
      var self = this;
   },

   didInsertElement: function() {
      this._super();
      var self = this;
      var biome_uri = self._options.biome_src;
      var kingdom_uri = self._options.starting_kingdom;
      self.$('#loadoutScreen').addClass(biome_uri);
      self.$('#loadoutScreen').addClass(kingdom_uri);

      // If faction has a specific loadout specification, repopulate using those loadouts
      self._loadoutsPath = self._options.loadouts || '/stonehearth/data/loadouts/loadouts.json';
      self._loadJson(self._loadoutsPath);

      self.$('#loadoutsList').on( 'click', '.loadoutRowSelectable', function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:focus' });
         self._deselectLoadout(self.get('selected').id);
         self._selectLoadout(this.getAttribute('loadout_id'));
      });

      $('#startButton').click(function() {
         self._start();
      });

      $('.quitButton').click(function() {
         App.stonehearthClient.quitToMainMenu('shellView', this);
      });
   },

   willDestroyElement: function() {
      self.$().off('click');
   },

   _loadJson: function(loadouts_path) {
      var self = this;
      $.getJSON(loadouts_path, function(data) {
         // Setup the loadouts list.
         function compareOrdinal(a, b) {
            return (a.ordinal || 0) > (b.ordinal || 0);
         }
         self._loadouts = {};
         var loadoutsList = [];
         radiant.each(data.loadouts, function (id, loadout) {
            loadout.id = id;
            loadout.content = radiant.map_to_array(loadout.content);
            loadout.content.sort(compareOrdinal);
            self._loadouts[id] = loadout;
            loadoutsList.push(loadout);
         });
         loadoutsList.sort(compareOrdinal);
         self.set('loadoutsList', loadoutsList);

         // Set up pets data.
         self.set('petsList', data.random_pets || []);
         self.set('petsCheckboxShown', self.get('petsList').length > 0);

         // Select the first loadout after all the divs have been rendered and thus have the appropriate attributes.
         if (loadoutsList.length) {
            Ember.run.scheduleOnce('afterRender', this, function () {
               self._selectLoadout(loadoutsList[0].id);
            });
         }
      });
   },

   _deselectLoadout: function(id) {
      $('[loadout_id="' + id + '"]').children('.loadoutRowBorder').removeClass('selectedLoadout');
   },

   _selectLoadout: function(id) {
      var self = this;
      self.set('selected', self._loadouts[id]);
      $('[loadout_id="' + id + '"]').children('.loadoutRowBorder').addClass('selectedLoadout');
   },

   _settleOrEmbark() {
      var self = this;
      radiant.call_obj('stonehearth.game_creation', 'is_world_generated_command')
         .done(function(e) {
            radiant.call_obj('stonehearth.terrain', 'set_fow_command', false);
            if (e.already_generated) {
               radiant.call('stonehearth:embark_client');
               App.navigate('game');
               radiant.call('radiant:reload_browser');
            } else {
               App.navigate('shell/select_settlement', {options: self._options, analytics: self._analytics});
            }
            self.destroy();
         })
         .fail(function(e) {
            console.error('checking if world already generated failed: ', e);
         });
   },

   _start: function() {
      var self = this;
      radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:embark'});

      var selected = self.get('selected');

      radiant.each(selected.content, function (i, content) {
         if (!content) return;  // Protect against broken mods.
         if (content.type == 'pet') {
            if (!self._options.starting_pets.push) {
               // It's an object rather than an array, thanks to Lua.
               self._options.starting_pets = [];
            }
            self._options.starting_pets.push(content.uri);
         } else if (content.type == 'gold') {
            self._options.starting_gold = content.amount;
         } else {
            self._options.starting_items[content.uri] = content.amount;
         }
      });
      
      var petsList = self.get('petsList');
      var petsCheckbox = self.$('#petsCheckbox');
      if (petsCheckbox && petsCheckbox.is(':checked')) {
         self._options.starting_pets = [petsList[Math.floor(Math.random() * petsList.length)]];
      }

      radiant.call_obj('stonehearth.population', 'update_player_options_command', self._options)
         .done(function(e) {
            self._settleOrEmbark();
         })
         .fail(function(e) {
            console.error('updating options (loadout) failed:', e);
         });
   }
});


// App.StonehearthLoadoutScreenView.reopen({
//    willDestroyElement: function() {
//       var self = this;
//       self.$().off('click');
//       self.$().find('.tooltipstered').tooltipster('destroy');
//    },

//    // for some reason, the loadout item icons are "underneath" the main row divs, so they don't get hovered
//    // also, just name and description isn't very useful, so don't bother with tooltips unless we increase their utility
   
//    // _selectLoadout: function(id) {
//    //    var self = this;
//    //    //self._super(id);

//    //    Ember.run.scheduleOnce('afterRender', this, function() {
//    //       self.$('.loadoutContentColumn').each((i, el) => {
//    //          var div = $(el);
//    //          var uri = div.attr('data-uri');
//    //          var catalogData = App.catalog.getCatalogData(uri);
//    //          if (catalogData) {
//    //             var tooltipString = App.tooltipHelper.createTooltip(i18n.t(catalogData.display_name), i18n.t(catalogData.description));
//    //             App.tooltipHelper.attachTooltipster(div, $(tooltipString));
//    //          }
//    //       });
//    //    });
//    //    self.set('selected', self._loadouts[id]);
//    //    $('[loadout_id="' + id + '"]').children('.loadoutRowBorder').addClass('selectedLoadout');
//    // }
// });
