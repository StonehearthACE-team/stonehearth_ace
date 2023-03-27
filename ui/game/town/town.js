// The view that shows a list of citizens and lets you promote one
App.StonehearthTownView = App.View.extend({
   templateName: 'town',
   classNames: ['flex', 'fullScreen', 'exclusive'],
   closeOnEsc: true,

   uriProperty: 'model',

   journalData: {
      'initialized' : false,
      'data' : null
   },
   lastClickedUri: null,
   lastClickedItem: null,

   init: function() {
      var self = this;
      this.journalData.initialized = false;
      this._super();
      self.set('town_name', App.stonehearthClient.settlementName())

      App.jobController.addChangeCallback('town', function() {
         self.set('num_workers', App.jobController.getNumWorkers());
         self.set('num_crafters', App.jobController.getNumCrafters());
         self.set('num_soldiers', App.jobController.getNumSoldiers());
      }, true);

      self.radiantTrace  = new RadiantTrace()
      self.scoreTrace = self.radiantTrace.traceUri(App.stonehearthClient.gameState.scoresUri, {});
      self.scoreTrace.progress(function(eobj) {
            self.set('score_data', eobj);
         });

      radiant.call('stonehearth:get_journals')
         .done(function(response){
            var uri = response.journals;

            if (uri == undefined) {
               //we don't have journals yet. Return
               //Since journals don't live update, it's OK to not listen for them.
               return;
            }

            self.radiantTraceJournals = new RadiantTrace();
            self.traceJournals = self.radiantTraceJournals.traceUri(uri, {});
            self.traceJournals.progress(function(eobj) {
                  self.journalData.data = eobj;
                  if (eobj.journals_by_page.size > 0) {
                     if (!self.journalData.initialized) {
                        self.journalData.initialized = true;
                        self._populatePages();
                     }
                  }
               });
         });

      var self = this;
      radiant.call('stonehearth:get_town')
         .done(function (response) {
            self._townTrace = new StonehearthDataTrace(response.result, { 'town_bonuses': { '*': {} }, 'default_storage': { '*': {}} })
               .progress(function (response) {
                  if (self.isDestroyed || self.isDestroying) {
                     return;
                  }

                  self._townDataChanged(response);
               });
         });

      radiant.call('stonehearth:get_current_immigration_requirements')
         .done(function (response) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            self.set('foodImmigrationRequirement', response.food);
            self.set('netWorthImmigrationRequirement', response.net_worth);
         });
      
   },

   destroy: function() {
      App.jobController.removeChangeCallback('town');

      if (this.radiantTrace) {
         this.radiantTrace.destroy();
      }

      if (this.radiantTraceJournals) {
         this.radiantTraceJournals.destroy();
         this.radiantTraceJournals = null;
      }

      if (this._playerInventoryTrace) {
         this._playerInventoryTrace.destroy();
      }

      this._super();
   },

   didInsertElement: function() {
      var self = this;
      this._super();

      this.$().draggable({ handle: '.title' });

      var rows = self.$('#scores .row').each(function( index ) {
         var row =  $( this );
         var scoreName = row.attr('id');
         var tooltipString = App.tooltipHelper.getTooltip(scoreName, null, true); // True for town description.
         if (tooltipString) {
            row.tooltipster({
                  content: $(tooltipString)
               });
         }
      });
      
      App.tooltipHelper.createDynamicTooltip(self.$('#workers'), function () {
         return i18n.t('stonehearth:ui.game.town_overview.num_workers');
      });
      App.tooltipHelper.createDynamicTooltip(self.$('#crafters'), function () {
         return i18n.t('stonehearth:ui.game.town_overview.num_crafters');
      });
      App.tooltipHelper.createDynamicTooltip(self.$('#soldiers'), function () {
         return i18n.t('stonehearth:ui.game.town_overview.num_soldiers');
      });

      this._updateUi();

      //inventory tab
      // ACE: add click handler to cycle through items, and search filter
      self._inventoryPalette = self.$('#inventoryPalette').stonehearthItemPalette({
         cssClass: 'inventoryItem',
         click: function (item) {
               // when the player clicks an inventory item, we want to try to select and go to that item
               // check if this was the last clicked item; if so, and it has count > 1, lookup "next" actual item for it
               var uri = item.attr('uri');
               var item_quality = item.attr('item_quality');
               var items = self.getItemsFromUri(uri, item_quality);
               if (items.length > 0) {
                  if (uri != self.lastClickedUri) {
                     self.lastClickedUri = uri;
                     self.lastClickedItem = null;
                  }
                  var nextItem = 0;
                  if (self.lastClickedItem) {
                     nextItem = (items.indexOf(self.lastClickedItem) + 1) % items.length;
                  }
                  self.lastClickedItem = items[nextItem];

                  radiant.call('stonehearth_ace:get_item_container', self.lastClickedItem)
                     .done(function(response) {
                        if (self.isDestroyed || self.isDestroying) {
                           return;
                        }
                        var camera_focus = self.lastClickedItem;
                        if (response.container && response.container != '') {
                           // if it's a universal_storage, the response will also contain access_nodes; just use the first one that's in the world
                           if (response.access_nodes) {
                              for (var i = 0; i < response.access_nodes.length; i++) {
                                 var access_node = response.access_nodes[i];
                                 if (access_node.in_world) {
                                    camera_focus = access_node.entity;
                                    break;
                                 }
                              }
                           }
                           else {
                              camera_focus = response.container;
                           }
                        }
                        // select and focus on the item, but if the item is in a container, focus on the container
                        radiant.call('stonehearth:select_entity', self.lastClickedItem);
                        radiant.call('stonehearth:camera_look_at_entity', camera_focus);
                     });
               }
         }
      });
      self._inventoryPalette.stonehearthItemPalette('showSearchFilter');

      radiant.call_obj('stonehearth.inventory', 'get_inventory_capacity_command')
         .done(function(response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }
            self.set('inventory_capacity', response.capacity);
         });

      radiant.call_obj('stonehearth.inventory', 'get_item_tracker_command', 'stonehearth:basic_inventory_tracker')
         .done(function(response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }

            var itemTraces = {
               "tracking_data" : {
                  "stonehearth:loot:gold" : {
                     "items" : {
                        "*" : {
                           "stonehearth:stacks": {}
                        }
                     }
                  }
               }
            };

            if (!self._inventoryPalette) {
               return;
            }
            self._playerInventoryTrace = new StonehearthDataTrace(response.tracker, itemTraces)
               .progress(function (response) {
                  self._inventoryTrackingData = response.tracking_data;
                  self._updateItems();
               });
         })
         .fail(function(response) {
            console.error(response);
         });

      // ACE: add tooltip for default storage
      App.tooltipHelper.attachTooltipster(self.$('#defaultStorageLabel'),
         $(App.tooltipHelper.createTooltip(null, i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.default_storage.tooltip')))
      );
      this.$('#overviewTab').show();
   },

   _townDataChanged: function(data) {
      var self = this;
      var bonuses = [];
      radiant.each(data.town_bonuses, (uri, bonus) => {
         bonuses.push({ display_name: bonus.display_name, description: bonus.description });
      });
      self.set('townBonuses', bonuses);

      self._defaultStorage = data.default_storage;
      self._updateDefaultStorage();
   },

   _updateItems: $.throttle(250, function () {
      var self = this;
      if (!self.$()) return;

      var inventoryItems = {}
      var totalNumItems = 0;
      // merge iconic and root entities
      radiant.each(self._inventoryTrackingData, function (uri, uri_entry) {
         radiant.each(uri_entry.item_qualities, function (item_quality_key, item) {
            var rootUri = uri;
            var isIconic = false;
            if (uri_entry.canonical_uri && uri_entry.canonical_uri != uri_entry.uri) {
               isIconic = true;
               rootUri = uri_entry.canonical_uri;
            }
            var key = rootUri + App.constants.item_quality.KEY_SEPARATOR + item_quality_key;
            var displayedCount = item.count;
            if (uri == 'stonehearth:loot:gold') {
               // Hack to sum up gold stacks.
               displayedCount = 0;
               radiant.each(uri_entry.items, function (_, item) {
                  displayedCount += item['stonehearth:stacks'].stacks;
               });
            }
            if (!inventoryItems[key]) {
               inventoryItems[key] = radiant.shallow_copy(uri_entry);
               inventoryItems[key].count = displayedCount;
               inventoryItems[key].item_quality = item_quality_key;
            } else {
               inventoryItems[key].count = inventoryItems[key].count + displayedCount;
            }

            // don't show undeployed tip for equipment
            var catalogData = App.catalog.getCatalogData(rootUri) || {};
            if (isIconic && !catalogData.equipment_roles) {
               var numUndeployed = item.count;
               // Add an additional tip to the item for the number of undeployed items in the world.
               inventoryItems[key].additionalTip = i18n.t('stonehearth:ui.game.entities.tooltip_num_undeployed', { num_undeployed: numUndeployed });
            }
            totalNumItems += item.count;
         });
      });

      self._inventoryPalette.stonehearthItemPalette('updateItems', inventoryItems);

      self.set('inventory_item_count', totalNumItems);
   }),

   willDestroyElement: function() {
      var self = this;

      this._inventoryPalette.stonehearthItemPalette('destroy');
      this._inventoryPalette = null;

      this.$('.book').unbind('turned');
      this.$('.book').off('click', '.odd');
      this.$('.book').off('click', '.even');
      if (this.$('.book').hasClass('turned')) {
         this.$('.book').turn('destroy');
      }
      this.$('#town').find('.tooltipstered').tooltipster('destroy');

      App.tooltipHelper.removeDynamicTooltip(self.$('[title]'));
      App.tooltipHelper.removeDynamicTooltip(self.$('#workers'));
      App.tooltipHelper.removeDynamicTooltip(self.$('#crafters'));
      App.tooltipHelper.removeDynamicTooltip(self.$('#soldiers'));

      this._super();
   },

   //Page 1 of the book is a title page
   //Open to at least page 2, or the most recent praise page
   _bookInit: function(bookPage) {
      var self = this;
      this.$('.book').turn({
                     display: 'double',
                     acceleration: true,
                     gradients: true,
                     elevation:50,
                     page: bookPage,
                     turnCorners: "",
                     when: {
                        turned: function(e, page) {
                           //console.log('Current view: ', $(this).turn('view'));
                        }
                     }
                  });

      this.$('.book').bind('turned', function(event, page, view) {
         if (page > 1) {
            var index = Math.floor(page / 2) - 1  + self.journalData.data.journal_start_index;
            var pageData = self.journalData.data.journals_by_page[index];
            if (pageData) {
               self._setDate(pageData.date);
            }
         }
      });

      this.$('.book').on( 'click', '.odd', function() {
        self._turnForward();
      });

      this.$('.book').on( 'click', '.even', function() {
         self._turnBack();
      });
   },

   //Town related stuff

   _updateUi: function() {
      var self = this;

      // Update net worth
      var netWorthLevel = self.get('score_data.net_worth.level');

      // Update town label.
      if (netWorthLevel) {
         var settlementSize = i18n.t('stonehearth:ui.game.town_overview.networth.size.' + netWorthLevel);
         $('#descriptor').html(i18n.t('stonehearth:ui.game.town_overview.networth.town_description', {
               "descriptor": i18n.t('stonehearth:ui.game.town_overview.networth.morale_descriptor.' + Math.floor(overallMoral/10)),
               "noun": settlementSize,
               "town_name": self.get('town_name'),
            }));
      }

      // Update happiness score
      self._updateHappinessScore();

      var setValueFloored = function(key_name, value) {
         if (!value) {
            value = 0;
         }
         self.set(key_name, Math.floor(value));
      };

      setValueFloored('net_worth', self.get('score_data.total_scores.net_worth'));
      setValueFloored('edibles', self.get('score_data.total_scores.edibles'));
      setValueFloored('military_strength', self.get('score_data.total_scores.military_strength'));

      setValueFloored('score_buildings', self.get('score_data.category_scores.buildings'));
      setValueFloored('score_inventory', self.get('score_data.category_scores.inventory'));
      setValueFloored('score_agriculture', self.get('score_data.category_scores.agriculture'));
   },

   _updateHappinessScore: function() {
      var self = this;
      var scoreValue = self.get('score_data.median.happiness');
      if (!scoreValue) {
         return;
      }

      var moodNumber = Math.round(scoreValue);
      var moodString, icon;
      $.each(App.happinessConstants.mood_data, function(mood, data) {
         if (data.score == moodNumber) {
            moodString = mood;
            icon = data.icon;
         }
      });

      if (!moodString) {
         console.log('no mood found in happiness constants matching a happiness score of ', moodNumber);
      }

      self.set('morale_icon_style', 'background-image: url(' + icon + ')');

      // Set the tooltip for the bar
      var tooltipString = App.tooltipHelper.getTooltip(moodString, null, true); // True for town description.
      var moraleBanner = $('#moraleBanner');
      if (tooltipString) {
         // Remove old mood tooltip if it exists
         if (moraleBanner.hasClass('tooltipstered')) {
            moraleBanner.tooltipster('destroy');
         }
         moraleBanner.tooltipster({
               content: $(tooltipString)
            });
      }
   },

   _setIconClass: function(className, value) {
      var iconValue = Math.floor(value / 10); // value between 1 and 10
      this.set(className, 'happiness_' + iconValue);
   },

   _observerScores: function() {
      this._updateUi();
   }.observes('score_data.happiness'),

   _updateMeter: function(element, value, text) {
      element.progressbar({
         value: value
      });

      element.find('.ui-progressbar-value').html(text.toFixed(1));
   },

   //Journal related stuff

   //Take the journal data, make a bunch of pages from it
   //Put those pages under the right parent to make the book
   //Clean out the old pages before appending the new ones.
   _populatePages: function() {
      var allPages = '<div><div><div id="bookBeginning"><h2>' + App.stonehearthClient.settlementName() +  '</h2><p>' +  i18n.t('stonehearth:ui.game.town_overview.journal.town_log') + '</p></div></div></div>';
      var jbp = this.journalData.data.journals_by_page;
      var startIndex = this.journalData.data.journal_start_index;
      for (var i = 0; i < jbp.size; i++) {
         var index = i + startIndex;
         allPages += this._makePages(jbp[index]);
      }

      var book = this.$(".book");
      if (!book) {
         // Book doesn't exist somehow. Perhaps this is being called before didInsertElement
         return;
      }

      book.empty();
      book.append(allPages);

      var lastIndex = jbp.size + startIndex - 1;
      this._setDate(jbp[lastIndex].date);

      // Turn to the most recent page; each journal entry consists of two pages (gripes and praises),
      // hence the multiplication.
      this._bookInit(jbp.size * 2);
   },

   _makePages: function(entries) {
      var allEntries = this._makeEntry(
         'gripeTitle',
         i18n.t('stonehearth:ui.game.town_overview.journal.gripes'),
         i18n.t('stonehearth:ui.game.town_overview.journal.gripe_empty'),
         entries.downs);
      allEntries += this._makeEntry(
         'praiseTitle',
         i18n.t('stonehearth:ui.game.town_overview.journal.praises'),
         i18n.t('stonehearth:ui.game.town_overview.journal.praise_empty'),
         entries.ups);

      return allEntries;
   },

   _makeEntry: function(className, titleText, emptyText, entries) {
      var allEntries = '<div><div><h2 class="' + className + '">' +  titleText + '</h2>';
      if (!entries.length) {
         allEntries += emptyText;
      } else {
         radiant.each(entries, function(j, entry) {
            var entryString = "<p class=\"logEntry\"><span class=\"logTitle\">"
                              + i18n.t(entry.title, {entry: entry}) + "</span></br>"
                              + i18n.t(entry.text, {entry: entry}) + "</br><span class=\"signature\">--"
                              + i18n.t('stonehearth:ui.game.town_overview.journal.signature', {entry: entry}) + "</span></p>";
            allEntries += entryString;
         });
      }
      allEntries += '</div></div>';
      return allEntries;
   },

   _setDate: function(date) {
      var dateLocalized;
      if (date) {
         dateLocalized = i18n.t('stonehearth:ui.game.calendar.date_format_long', {date: date});
      } else {
         dateLocalized = i18n.t('stonehearth:ui.game.town_overview.journal.today');
      }

      this.$("#journalDate").html(dateLocalized);
   },

   _turnForward: function() {
      var page = $(".book").turn("page");

      if ( page != undefined ) {
         $('.book').turn('next');
      }
   },

   _turnBack: function() {
      var page = $(".book").turn("page");

      // never go to page 1
      if (page > 3) {
         $('.book').turn('previous');
      }
   },

   _updateInventoryCountClass: function() {
      var self = this;
      var capacity = self.get('inventory_capacity');
      var count = self.get('inventory_item_count');
      if (count && capacity && count >= capacity) {
         var countNumbers = self.$('#countNumbers');
         countNumbers.removeClass('notFull');
         countNumbers.addClass('fullWarning');

         // If inventory is full, also add a warning to the tab.
         if (!self._inventoryTabStatus) {
            var inventoryTabButton = self.$('#inventoryTabButton');
            var position = inventoryTabButton.position().left;
            var width = inventoryTabButton.width();
            self._inventoryTabStatus = App.statusHelper.addStatus(inventoryTabButton, 'error_icon.png', 0, position + width, true);

            var tooltipString = App.tooltipHelper.createTooltip(i18n.t('stonehearth:ui.game.bulletin.inventory_full.title'),
                                                               i18n.t('stonehearth:ui.game.bulletin.inventory_full.message'));
            if (tooltipString) {
               inventoryTabButton.tooltipster({
                     content: $(tooltipString)
                  });
               var inventoryCountElement = self.$('#inventoryCount');
               inventoryCountElement.tooltipster({
                     content: $(tooltipString)
                  });
            }

         }
      } else {
         self.$('#countNumbers').removeClass('fullWarning');
         self.$('#countNumbers').addClass('notFull');
         if (self._inventoryTabStatus) {
            var inventoryTabButton = self.$('#inventoryTabButton');
            inventoryTabButton.tooltipster('destroy');

            var inventoryCountElement = self.$('#inventoryCount');
            inventoryCountElement.tooltipster('destroy')

            App.statusHelper.removeStatus(self._inventoryTabStatus);
            self._inventoryTabStatus = null;
         }
      }
   }.observes('inventory_item_count', 'inventory_capacity'),

   // ACE: default storage and inventory click item cycling functionality
   _updateDefaultStorage: $.throttle(250, function () {
      var self = this;
      if (!self.$()) return;

      var items = [];
      radiant.each(self._defaultStorage, function (id, storage) {
         var catalogData = App.catalog.getCatalogData(storage.uri);
         if (catalogData) {
            var item = {
               id: id,
               entityId: storage.__self,
               icon: catalogData.icon
            };
            items.push(item);
         }
      });

      self.set('defaultStorage', items);
      self.set('hasDefaultStorage', items.length > 0);

      Ember.run.scheduleOnce('afterRender', this, function() {
         var elements = self.$('.defaultStorageItem');
         if (elements) {
            elements.each(function() {
               var $el = $(this);
               var entity = self._getDefaultStorageEntity($el.attr('storage-id'));
               var catalogData = App.catalog.getCatalogData(entity.uri);
               App.tooltipHelper.createDynamicTooltip($el, function () {
                  return $(App.tooltipHelper.createTooltip(i18n.t(catalogData.display_name), i18n.t(catalogData.description)));
               });
            });
         }
      });
   }),

   getItemsFromUri: function (this_uri, this_quality) {
      var self = this;
      var items = [];

      if (this_uri) {
         this_uri = this_uri.replace('.', '&#46;');
         var canonical_uri = self._inventoryTrackingData[this_uri].canonical_uri;
         if (!canonical_uri) {
            canonical_uri = this_uri;
         }
         radiant.each(self._inventoryTrackingData, function (_, uri_entry) {
            if (canonical_uri == uri_entry.uri || canonical_uri == uri_entry.canonical_uri) {
               radiant.each(uri_entry.item_qualities, function (item_quality_key, item_of_quality) {
                  if (item_quality_key == this_quality) {
                     radiant.each(item_of_quality.items, function (_, item) {
                        items.push(item);
                     });
                  }
               });
            }
         });
      }

      return items;
   },

   _getDefaultStorageEntity: function(id) {
      return this._defaultStorage && this._defaultStorage[id];
   },

   actions: {
      back: function() {
         this._turnBack();
      },
      forward: function() {
         this._turnForward();
      },
      goToDefaultStorage: function(id) {
         var entity = this._getDefaultStorageEntity(id);
         var entityId = entity && entity.__self;
         if (entityId) {
            radiant.call('stonehearth:select_entity', entityId);
            radiant.call('stonehearth:camera_look_at_entity', entityId);
         }
      }
   }

});
