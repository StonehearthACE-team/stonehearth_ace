App.StonehearthBuildingFixtureListView = App.View.extend({
   templateName: 'fixtureList',

   // ACE: added more categories
   categories: {
      mercantile: true,
      training_equipment: true,
		mechanism: true,
		herbalist_planter: true,
		fluid_control: true,
		decoration: true,
      construction: true,
      door: true,
      furniture: true,
      workshops: true,
      storage: true,
      window: true
   },

   init: function() {
      var self = this;
      self._inventoryData = {};
      self._super();
   },

   didInsertElement: function() {
      var self = this;
      this._super();

      self.$('#fixtures').on('click', '.fixture', function() {
         var el = $(this);
         self._fixtureClick(el.data('fixture_uri'), el.data('item_quality'));
         self.$('#fixtures').find('.fixture').removeClass('selected');
         el.addClass('selected');
      });

      radiant.call_obj('stonehearth.inventory', 'get_item_tracker_command', 'stonehearth:placeable_item_inventory_tracker')
         .done(function(response) {
            self._trace = new StonehearthDataTrace(response.tracker, {})
               .progress(function (response) {
                  self._placeableItems = response.tracking_data;
                  if (self.get('isVisible') && self.get('parentView').get('isVisible')) {  // Ugghh
                     self._updateInventoryData();
                  }
               });
         })
         .fail(function(response) {
            console.error(response);
         });

      //  When someone's job or level changes, let us know.
      App.jobController.addChangeCallback('fixture_list', function() {
            self._updateItems();
         }, true);
      Ember.run.scheduleOnce('afterRender', self, '_updateFixtureTooltips');

      self.$().on('keyup', '.searchInput', function() {
         var text = $(this).val();
         self._filterFixtures(text.toLowerCase());
         self._setSearchbarsText(text);
      });
      self.$('#fixtures').children().hide();
   },

   willDestroyElement: function() {
      this.$().find('.tooltipstered').tooltipster('destroy');
      this._super();
   },

   _updateFixtureTooltips: function() {
      self.$('.fixturesKind').each(function() {
         var tooltipString = $(this).attr('tooltip');
         App.tooltipHelper.createDynamicTooltip($(this), function () {
            return tooltipString;
         });
      });
   },

   _updateFixtureItemTooltips: function() {
      self.$('.fixture').each(function() {
         var tooltipString = $(this).data('tooltip');
         App.tooltipHelper.createDynamicTooltip($(this), function () {
            return $(App.tooltipHelper.createTooltip(null, tooltipString));;
         });
      });
   },

   _fixtureClick: function(fixtureUri, itemQuality) {
      radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_select_button'});
      this.send('addFixture', fixtureUri, itemQuality);
   },

   _reactToVisibilityChanged: function () {
      var self = this;
      if (self.get('isVisible') && self.get('parentView').get('isVisible')) {  // Ugghh
         self._updateInventoryData();
      }
   }.observes('isVisible', 'parentView.isVisible'),

   _updateInventoryData: function () {
      var self = this;
      self._inventoryData = {};

      _.forEach(self._placeableItems, function (uri_entry, uri) {
         _.forEach(uri_entry.item_qualities, function(item, item_quality_key) {
            var entry = radiant.shallow_copy(item);
            entry.uri = uri_entry.uri;
            entry.iconic_uri = uri_entry.iconic_uri;
            if (entry.count > 0) {
               var catalogData = App.catalog.getCatalogData(entry.uri);
               if (catalogData) {
                  self._appendCatalogData(entry, catalogData);
                  self._inventoryData[uri + App.constants.item_quality.KEY_SEPARATOR + item_quality_key] = entry;
               }
            }
         });
      });
      self._updateItems();
      Ember.run.scheduleOnce('afterRender', self, '_updateFixtureItemTooltips');
   },

   _updateItems: function() {
      var self = this;

      var allFixtures = radiant.shallow_copy(self._inventoryData);
      var craftableProducts = {};
      var jobData = App.jobController.getJobControllerData();
      if (!jobData || !jobData.jobs) {
         return;
      }

      _.forEach(jobData.jobs, function(jobControllerInfo, jobUri) {
         if (!jobControllerInfo.recipe_list) {
            return;
         }

         if (jobControllerInfo.num_members <= 0) {
            // do not show if nobody has been promoted to this crafter
            return;
         }

         var highestLevel = jobControllerInfo.highest_level;
         var jobInfo = App.jobConstants[jobUri];
         var jobIcon;
         if (jobInfo) {
            jobIcon = jobInfo.description.icon;
         }

         _.forEach(jobControllerInfo.recipe_list, function(category) {
            _.forEach(category.recipes, function(recipe_info, recipe_key) {
               var recipe = recipe_info.recipe;
               if (recipe.level_requirement > highestLevel) {
                  // do not show if no one can craft it
                  return;
               }

               if (recipe.manual_unlock && !jobControllerInfo.manually_unlocked[recipe.recipe_key]) {
                  // do not show if no one can craft it
                  return;
               }

               var product_uri = recipe.product_uri;
               var catalogData = App.catalog.getCatalogData(product_uri);
               if (!catalogData) {
                  // No data for the product or product is not a placeable item
                  return;
               }

               if (!self.categories[catalogData.category]) {
                  return;
               }

               var entry = {
                  uri: product_uri,
                  item_quality: -1,
                  jobIcon: jobIcon,
               };

               self._appendCatalogData(entry, catalogData);
               craftableProducts[product_uri] = entry;
            });
         });
      });

      // Merge placeable fixes and recipes
      _.forEach(craftableProducts, function(data, rootUri) {
         var key = rootUri + '+1';  // Merge with the "quality 1" version.
         if (!allFixtures[key]) {
            allFixtures[key] = data;  // Merge with the "quality 1" version.
         }
         else {
            allFixtures[key].jobIcon = data.jobIcon;
         }
      });

      self._updateView(allFixtures);
   },

   _appendCatalogData: function(entry, catalogData) {
      entry.category = catalogData.category;
      entry.description = catalogData.description;
      entry.display_name = catalogData.display_name;
      entry.appeal = catalogData.appeal;
      entry.icon =  catalogData.icon;
   },

   _getUri: function(item) {
      var uri = item.uri.__self ? item.uri.__self : item.uri;
      return uri;
   },

   _updateView: function(allFixtures) {
      var self = this;
      self.set('items', {});

      var fixturesByCategory = {};

      _.forEach(allFixtures, function(data, uri) {
         var category = fixturesByCategory[data.category];
         if (!category) {
            category = {};
            fixturesByCategory[data.category] = category;
         }
         category[uri] = data;
      });

      _.forEach(fixturesByCategory, function(list, category) {
         var items = [];
         _.forEach(list, function(data, uri) {
            items.push(self._addItem(data));
         });
         self.set(category, items);
      });
   },

   _addItem: function(data) {
      var tooltip = i18n.t(data.display_name);
      if (data.count) {
         // if there's a number of them in inventory, show that
         tooltip += ` (${data.count})`;
      }

      if (data.jobIcon) {
         // if there's a crafter job icon, include that
         tooltip += `<img class="jobIcon" src="${data.jobIcon}"/>`;
      }

      var item = {
         style: "background-image: url(" + data.icon + ")",
         item_quality: data.item_quality || 1,
         item_quality_class: "quality-" + (data.item_quality || 1) + "-icon",
         tooltip: tooltip,
         data: data.uri
      };
      return item;
   },

   _filterFixtures: function(text) {
      var self = this;

      var fixtures = self.$('#fixtures').find('.fixture');
      fixtures.show();

      var queryTerms = text.toLowerCase().split(/\s+/g);
      queryTerms.forEach(function(term) {
         fixtures.each(function() {
            var data = $(this).data('tooltip') + '';
            if (data.toLowerCase().indexOf(term.toLowerCase()) == -1) {
               $(this).hide();
            }
         });
      });
   },

   _setSearchbarsText: function(text) {
      var self = this;

      self.$('#doorSearch .searchInput').val(text);
      self.$('#windowSearch .searchInput').val(text);
      self.$('#decorationSearch .searchInput').val(text);
      self.$('#furnitureSearch .searchInput').val(text);
   },

   willDestroyElement: function() {
      this.$().off('keyup', '.searchInput');
      this._super();
   },

   actions: {
      changeFixture: function(fixtureKind) {
         var self = this;

         var alreadySelected = self.$('#' + fixtureKind + 'Kind').hasClass('selected');
         self.$('#fixtures').children().hide();
         self.$('#fixtureKinds').children().removeClass('selected');
         if (!alreadySelected) {
            self.$('#' + fixtureKind).show();
            self.$('#' + fixtureKind + 'Kind').addClass('selected');
         }
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_select_button'});
      },

      clearSelectedFixture: function() {
         var self = this;
         self.$('#fixtures').find('.fixture').removeClass('selected');
      },

      addFixture: function(fixtureUri, itemQuality) {
         var self = this;
         var quality = (itemQuality || -1) <= 1 ? -1 : itemQuality;
         radiant.call_obj('stonehearth.building', 'do_decoration_tool_command', fixtureUri, quality)
            .done(function() {
               self.send('addFixture', fixtureUri, quality);
            })
            .fail(function(e) {
               self.send('clearSelectedFixture');
               if (e.result != 'new_tool') {
                  radiant.call_obj('stonehearth.building', 'unset_tool_command');
               }
            });
      }
   }
});
