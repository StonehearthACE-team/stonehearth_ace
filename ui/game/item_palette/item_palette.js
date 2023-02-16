var debug_itemPaletteShowItemIds = false;
$.widget( "stonehearth.stonehearthItemPalette", {

   options: {

      click: function(item) {
      },

      filter: function(item) {
         return true;
      },

      cssClass: '',
      hideCount: false,
      // ACE: added more options
      showZeroes: false,
      skipCategories: false,
      sortField: 'display_name',
      wantedItems: null,
   },

   _create: function() {
      var self = this;

      self.palette = $('<div>').addClass('itemPalette');
      self._selectedElement = null;
      self._itemElements = {};
      self._categoryElements = {};

      function handleClick(itemSelected, e, callback) {
         radiant.call('radiant:play_sound', { 'track': 'stonehearth:sounds:ui:start_menu:popup' });
         if (self._selectedElement) {
            self._selectedElement.removeClass('selected');
         }
         self._selectedElement = itemSelected;
         itemSelected.addClass('selected');

         if (callback) {
            callback(itemSelected, e);
         }
         return false;
      }

      self.palette.on('click', '.item', function (e) { return handleClick($(this), e, self.options.click); });
      self.palette.on('contextmenu', '.item', function (e) { return handleClick($(this), e, self.options.rightClick); });

      self.element.append(this.palette);
   },

   _destroy: function() {
      // ACE: clear up extra resources we added
      var self = this;
      self.isDestroyed = true;
      if (self._unlocked_crops_trace) {
         self._unlocked_crops_trace.destroy();
      }
      self._unlocked_crops_trace = null;

      if (self.searchInput) {
         self.searchInput.off('keyup');
         self.searchInput.off('keydown');
         self.searchInput.off('blur');
      }
      if (self.searchBox) {
         self.searchBox.off('return');
      }

      App.tooltipHelper.removeDynamicTooltip(this.element);
      this.palette.off('click', '.item');
   },

   showSearchFilter: function() {
      var self = this;
      self.searchBox = $('<div>').addClass('itemPaletteSearchBox').addClass('collapsed');
      self.searchInput = $('<input>').attr('placeholder', i18n.t('stonehearth:ui.game.show_workshop.placeholder'));

      self.searchBox.mousedown(function (e) {
         if (self.searchBox.hasClass('collapsed')) {
            self.searchBox.removeClass('collapsed');
            self.searchInput.focus();
            e.stopPropagation();
            return false;
         }
      });

      self.searchInput.keydown(function (e) {
         if (e.key == 'Escape') {
            e.stopPropagation();
         }
      });
      self.searchInput.keyup(function (e) {
         if (e.key == 'Escape') {
            self.searchInput.val('');
            e.stopPropagation();
         }
         self._updateAllItemsSearchFilter();
         if (e.key == 'Enter' || e.key == 'Escape') {
            self.searchInput.blur();
         }
      });
      self.searchInput.blur(function (e) {
         if (!self.searchInput.val()) {
            self.searchBox.addClass('collapsed');
         }
      });

      self.searchBox.append(self.searchInput);
      self.palette.append(self.searchBox);
   },

   // ACE: handle "wanted items" functionality for shop dialogs
   updateWantedItems: function(wantedItems) {
      var self = this;
      self.options.wantedItems = wantedItems;
      radiant.each(self._itemElements, function(uri, itemQualities) {
         radiant.each(itemQualities, function(quality, el) {
            if (el != null) {
               self._updateWantedItem(el, uri);
            }
         });
      });
   },

   updateSoldItems: function(soldItems) {
      var self = this;
      self.options.soldItems = soldItems;
      radiant.each(self._itemElements, function(uri, itemQualities) {
         radiant.each(itemQualities, function(quality, el) {
            if (el != null) {
               self._updateWantedItem(el, uri);
            }
         });
      });
   },

   // ACE: handle extra information about equipment and whether an item unlocks a crop
   updateItems: function(itemMap) {
      var self = this;

      // Start off with all items marked as not updated.
      var updated = {
         items: {},
         categories: {},
      };

      // Convert item entries for display.
      var hasCropUnlocks = false;
      var arr = radiant.map_to_array(itemMap, function(k, v){
         var uri = self._getRootUri(v);
         if (uri) {
            var catalogData = App.catalog.getCatalogData(uri);
            // only include an item that has an icon
            if (catalogData && catalogData.icon) {
               v.root_uri = uri;
               v.display_name = catalogData.display_name;
               v.description = catalogData.description;
               v.category = v.category || catalogData.category;   // don't override a manually supplied category
               v.icon = catalogData.icon;
               v.item_quality = v.item_quality || 1;
               v.deprecated = catalogData.deprecated;
               v.equipment_required_level = catalogData.equipment_required_level;
               v.equipment_roles = catalogData.equipment_roles;
               v.equipment_types = catalogData.equipment_types;
               v.unlocks_crop = catalogData.unlocks_crop;

               if (v.unlocks_crop) {
                  hasCropUnlocks = true;
               }

               return v;
            }
         }
         return false;  // Skip items with no URI or catalog data.
      });

      if (hasCropUnlocks) {
         if (self._unlocked_crops_trace == null) {
            self._unlocked_crops_trace = false;
            radiant.call_obj('stonehearth.job', 'get_job_call', 'stonehearth:jobs:farmer')
               .done(function (response) {
                  if (self.isDestroyed) return;
                  if (response.job_info_object) {
                     self._unlocked_crops_trace = new StonehearthDataTrace(response.job_info_object)
                        .progress(function (response) {
                           if (self.isDestroyed) return;
                           self._unlocked_crops = response.manually_unlocked;
                        });
                  }
               });
         }

         if (!self._all_crops) {
            radiant.call('stonehearth:get_all_crops')
               .done(function (o) {
                  if (self.isDestroyed) return;
                  self._all_crops = o.all_crops;
               });
         }
      }

      // Sort all items globally. This ensures they are sorted within their categories on first add (but not subsequent ones).
      var sortField = self.options.sortField;
      arr.sort(function(a, b){
         var aName = a[sortField];
          var bName = b[sortField];
          if (aName > bName) {
            return 1;
          }
          if (aName < bName) {
            return -1;
          }
          // a must be equal to b
          return 0;
      });
      self._itemArr = arr;

      // Go through each item and update the corresponding DOM element for it.
      radiant.each(self._itemArr, function(i, item) {
         var itemCount = self._getCount(item);
         if (self.options.filter(item) && (self.options.showZeroes || itemCount > 0)) {
            var uri = self._getUri(item);
            var itemQuality = item.item_quality;
            var itemCategory = item.category;

            var itemElement = self._itemElements[uri] && self._itemElements[uri][itemQuality];
            var parent = self.palette;

            if (!self.options.skipCategories) {
               var categoryElement = self._categoryElements[itemCategory];

               if (!categoryElement) {
                  categoryElement = self._addCategoryForItem(item);
                  self._categoryElements[itemCategory] = categoryElement
               }
               parent = categoryElement.find('.downSection');
            }

            if (!itemElement) {
               var itemElements = self._itemElements[uri];
               if (!itemElements) {
                  self._itemElements[uri] = {};
               }
               itemElement = self._addItemElement(item)
               self._itemElements[uri][itemQuality] = itemElement;
               parent.append(itemElement);
            }

            self._updateItemElement(itemElement, item, uri);

            updated.categories[item.category] = true;
            if (!updated.items[uri]) updated.items[uri] = {};
            updated.items[uri][itemQuality] = true;
         }
      });

      // Anything that is not marked as updated needs to be removed.
      radiant.each(self._itemElements, function(uri, itemQualities) {
         radiant.each(itemQualities, function(quality, el) {
            if (el != null && !(updated.items[uri] && updated.items[uri][quality])) {
               App.tooltipHelper.removeDynamicTooltip(el);
               el.remove();
               if (self._itemElements[uri]) {
                  self._itemElements[uri][quality] = null;
               }
            }
         });
      });

      radiant.each(self._categoryElements, function(category, el) {
         if (el != null && !updated.categories[category]) {
            App.tooltipHelper.removeDynamicTooltip(el);
            el.remove();
            self._categoryElements[category] = null;
         }
      });

      // ACE: added category sorting
      // now sort each category according to its ordinal
      var categories = $(self.palette).find('.category');
      categories.sort(function(a, b) {
         return +$(a).attr('ordinal') - +$(b).attr('ordinal');
      });
      categories.appendTo(self.palette);

      self._updateAllItemsSearchFilter();
   },

   _findCategory: function(item) {
      var selector = "[category='" + item.category + "']";
      var match = this.palette.find(selector)[0];

      if (match) {
         return $(match);
      }
   },

   // ACE: handle category ordinals
   _addCategoryForItem: function(item) {
      var categoryData = stonehearth_ace.getItemCategory(item.category) || {};
      var ordinal = isNaN(categoryData.ordinal) ? 999 : categoryData.ordinal;

      var category = $('<div>')
         .addClass('category')
         .attr('category', item.category)
         .attr('ordinal', ordinal);

      // new title element for the category
      var categoryDisplayName = i18n.t(categoryData.display_name || 'stonehearth:ui.game.entities.item_categories.' + item.category);
      if (!categoryDisplayName) {
         console.log("No category display name found for item category " + item.category);
         categoryDisplayName = item.category;
      }

      $('<h2>')
         .html(categoryDisplayName)
         .appendTo(category)
         .click(function(){
            this.classList.toggle("collapsed");
         });

      // the category container element that items are inserted into
      $('<div>')
         .addClass('downSection')
         .appendTo(category);

      category.appendTo(this.palette);

      return category;
   },

   // ACE: added functionality for search filter and wanted items
   _updateAllItemsSearchFilter: function() {
      var self = this;
      var search = self.searchInput && self.searchInput.val().toLowerCase();
      if (search) {
         radiant.each(self._itemElements, function(uri, elements) {
            var catalogData = App.catalog.getCatalogData(uri);
            var tags = (catalogData.materials || []).slice();
            tags.push(i18n.t(catalogData.display_name).toLowerCase());
            tags.push(i18n.t(catalogData.description).toLowerCase());
            radiant.each(elements, function(quality, $el) {
               var parent = $el && $el.parent() && $el.parent().parent();
               if (parent) {
                  var category = parent.find('h2').text().toLowerCase();
                  self._updateItemSearchFilter(search, $el, category, tags);
               }
            });
         });
      }
      else {
         self.palette.find('.notInSearchFilter').removeClass('notInSearchFilter');
      }

      // then hide/unhide categories based on whether they have any unhidden elements
      var hasUnhidden = self.palette.find('.category').has('.item:not(.notInSearchFilter)');
      hasUnhidden.removeClass('notInSearchFilter');
      
      self.palette.find('.category').not(hasUnhidden).addClass('notInSearchFilter');
      if (self.searchBox) {
         if (hasUnhidden.length == 0) {
            self.searchBox.addClass('noUnhiddenCategories');
         }
         else {
            self.searchBox.removeClass('noUnhiddenCategories');
         }
      }
   },

   _updateItemSearchFilter: function(search, itemEl, category, tags) {
      var matches = category.includes(search);
      if (!matches) {
         for (var i = 0; i < tags.length; i++) {
            if (tags[i].includes(search)) {
               matches = true;
               break;
            }
         }
      }

      if (!matches) {
         itemEl.addClass('notInSearchFilter');
      }
      else
      {
         itemEl.removeClass('notInSearchFilter');
      }
   },

   _updateWantedItem: function(itemEl, uri) {
      var priceFactor = this._getBestPriceFactorForItem(uri);
      // update its wanted status
      if (priceFactor != 1) {
         itemEl.addClass('wantedItem');
         if (priceFactor > 1) {
            itemEl.addClass('higherPrice');
         }
         else if (priceFactor < 1) {
            itemEl.addClass('lowerPrice');
         }
      }
      else {
         itemEl.removeClass('wantedItem');
         itemEl.removeClass('higherPrice');
         itemEl.removeClass('lowerPrice');
      }

      if (this.options.updateWantedItem) {
         this.options.updateWantedItem(itemEl, priceFactor);
      }
   },

   _getBestPriceFactorForItem: function(uri, skipWanted) {
      var soldItems = this.options.soldItems;
      var bestWantedItem = !skipWanted && this._getBestWantedItem(uri);
      var factor = bestWantedItem && bestWantedItem.price_factor || 1;

      if (soldItems) {
         // WARNING: hard-coding max item quality as 4 (masterwork) for checks
         for (var i = 1; i <= 4; i++) {
            var key = uri + App.constants.item_quality.KEY_SEPARATOR + i;
            if (soldItems[key]) {
               return factor * App.constants.mercantile.DEFAULT_UNWANTED_ITEM_PRICE_FACTOR;
            }
         }
      }

      return factor;
   },

   _getBestWantedItem: function(uri) {
      var wantedItems = this.options.wantedItems;
      var bestWantedItem = null;
      
      if (wantedItems) {
         var catalogData = App.catalog.getCatalogData(uri);
         for (var i = 0; i < wantedItems.length; i++) {
            var wantedItem = wantedItems[i];
            if (!wantedItem.max_quantity || wantedItem.max_quantity > wantedItem.quantity) {
               if (!bestWantedItem || bestWantedItem.price_factor < wantedItem.price_factor) {
                  if (uri == wantedItem.uri ||
                        (wantedItem.material && catalogData.materials && !$.isEmptyObject(catalogData.materials) &&
                        radiant.isMaterial(catalogData.materials, wantedItem.material))) {
                     bestWantedItem = wantedItem;
                  }
               }
            }
         }
      }

      return bestWantedItem;
   },

   _getUri: function (item) {
      if (!item.uri) return undefined;
      var uri = item.uri.__self ? item.uri.__self : item.uri;
      return uri;
   },

   _addItemElement: function(item) {
      var img = $('<img>')
         .addClass('image')
         .attr('src', item.icon);

      var num = $('<div>')
         .addClass('num');

      var selectBox = $('<div>')
         .addClass('selectBox');

      var uri = this._getUri(item);

      var itemEl = $('<div>')
         .addClass('item')
         .addClass(this.options.cssClass)
         .attr('uri', uri)
         .attr('item_quality', item.item_quality)
         .append(img)
         .append(num)
         .append(selectBox);

      if (item.item_quality > 1) {
         $('<div>')
            .addClass('quality-' + item.item_quality + '-icon')
            .appendTo(itemEl);
      }

      if (this.options.itemAdded) {
         this.options.itemAdded(itemEl, item);
      }

      return itemEl;
   },

   _getCount: function(item) {
      if (item.count) {
         return item.count;
      } else if (item.items) {
         return Object.keys(item.items).length
      } else {
         return item.num || 0;
      }
   },

   // ACE: added showZeroes option and handling for wanted items
   _updateItemElement: function(itemEl, item, uri) {
      if (!this.options.hideCount) {
         var num = this._getCount(item);

         if (num == 0 && !this.options.showZeroes) {
            App.tooltipHelper.removeDynamicTooltip(itemEl);

            // Remove from item elements map
            if (self._itemElements[uri]) {
               delete self._itemElements[uri][item.quality];
            }
         } else {
            if (!num && !this.options.showZeroes) {
               itemEl.find('.num').html('');
            } else {
               itemEl.find('.num').html(num);
            }
         }

         if (this.options.wantedItems || this.options.soldItems) {
            this._updateWantedItem(itemEl, uri);
         }
      }

      this._updateItemTooltip(itemEl, item);
   },

   _geti18nVariables: function(item) {
      var itemSelf = {}

      var uri = this._getUri(item);
      // Only display the stack count for gold in a gold chest.
      var stackCount = 0;
      if (item.items) {
         radiant.each(item.items, function(id, individualItem) {
            var stacksComponent = individualItem && individualItem['stonehearth:stacks'];
            if (stacksComponent && stacksComponent.stacks) {
              stackCount += stacksComponent.stacks;
            }
         });
      }

      if (stackCount > 0) {
         itemSelf['stonehearth:stacks'] = {
            stacks: stackCount
         };
      }

      return {self: itemSelf, allowUntranslated: false};
   },

   _debugTooltip: function(item) {
      var tooltipString = "";
      if (item.items) {
         radiant.each(item.items, function(k, v) {
            tooltipString = tooltipString + k + ", ";

         });
      }
      return tooltipString;
   },

   _isCropUnlocked: function(crop) {
      var self = this;
      return (self._unlocked_crops && self._unlocked_crops[crop]) || (self._all_crops && self._all_crops[crop] && self._all_crops[crop].initial_crop)
   },

   // ACE: added various extra information, like equipment info, wanted items, and whether a crop is already unlocked
   _updateItemTooltip: function(itemEl, item) {
      if (itemEl.hasClass('tooltipstered')) {
         return;
      }

      var self = this;
      App.tooltipHelper.createDynamicTooltip(itemEl, function() {
         var translationVars = self._geti18nVariables(item);
         var displayNameTranslated = i18n.t(item.display_name, translationVars);
         if (item.deprecated) {
            displayNameTranslated = '<span class="item-tooltip-title item-deprecated">' + displayNameTranslated + '</span>';
         } else if (item.item_quality > 1) {
            displayNameTranslated = '<span class="item-tooltip-title item-quality-' + item.item_quality + '">' + displayNameTranslated + '</span>';
         }
         var description = "";
         if (item.description) {
            description = i18n.t(item.description, translationVars);
         }

         if (debug_itemPaletteShowItemIds) {
            description = description + '<p>' + self._debugTooltip(item) + '</p>'
         }

         var entity_data = self._getEntityData(item);
         var extraTip;
         if (entity_data) {
            var combat_info = "";

            var weapon_data = entity_data['stonehearth:combat:weapon_data'];
            if (weapon_data) {
               combat_info = combat_info +
                           '<span id="atkHeader" class="combatHeader">' + i18n.t('stonehearth:ui.game.entities.tooltip_combat_base_damage') + '</span>' +
                           '<span id="atkValue" class="combatValue">+' + weapon_data.base_damage + '</span>';
            }

            var armor_data = entity_data['stonehearth:combat:armor_data'];
            if (armor_data) {
               combat_info = combat_info +
                        '<span id="defHeader" class="combatHeader">' + i18n.t('stonehearth:ui.game.entities.tooltip_combat_base_damage_reduction') + '</span>' +
                        '<span id="defValue" class="combatValue">+' + armor_data.base_damage_reduction + '</span>'
            }

            if (combat_info != "") {
               description = description + '<div class="itemCombatData">' + combat_info + "</div>";
            }
         }

         var appeal_data = entity_data !== null ? entity_data['stonehearth:appeal'] : (item.appeal ? { 'appeal': item.appeal } : undefined);
         if (appeal_data) {
            var appeal = radiant.applyItemQualityBonus('appeal', appeal_data['appeal'], item.item_quality);
            if (appeal) {  // Ignore zero appeal
               extraTip = '<div class="item-appeal-tooltip">' + appeal + "</div>";
            }
         }
         
         if (item.deprecated) {
            description += '<div class="item-deprecated-tooltip">' + i18n.t('stonehearth:ui.game.entities.tooltip_deprecated') + "</div>";
         }

         if (item.additionalTip) {
            description = description + '<div class="itemAdditionalTip">' + item.additionalTip + "</div>";
         }

         if (item.unlocks_crop && self._isCropUnlocked(item.unlocks_crop)) {
            description = description + '<div class="itemAdditionalTip">' + i18n.t('stonehearth_ace:ui.game.entities.tooltip_crop_unlocked') + "</div>";
         }

         if (item.equipment_required_level || item.equipment_roles || item.equipment_types) {
            var levelDiv = item.equipment_required_level ?
                  `<div>${i18n.t('stonehearth:ui.game.unit_frame.level')}<span class="required-level"> ${item.equipment_required_level} </span></div>` : '';
            var rolesDiv = self._getEquipmentRolesDiv(item.equipment_roles);
            var typesDiv = self._getEquipmentTypesDiv(item.equipment_types);
            var equipDiv = `<div class="item-equipment-tooltip">${levelDiv}${rolesDiv}${typesDiv}</div>`;
            
            // we want to make sure that none of the regular description text overlaps these attributes in the top right
            // so just enclose the two in separate inline divs
            //description = `<div class="item-inline-tooltip">${description}</div>${equipDiv}`;
            extraTip = extraTip ? extraTip + equipDiv : equipDiv;
         }

         var wantedItem = self._getBestWantedItem(item.root_uri);
         if (wantedItem) {
            var quantity = wantedItem.max_quantity != null ? (wantedItem.max_quantity - wantedItem.quantity) : null;
            var hasQuantity = quantity != null;
            // show the percentage modification to the price
            var priceMod = Math.floor((wantedItem.price_factor - 1) * 100 + 0.5);
            if (priceMod > 0) {
               // price is increased
               description += '<div class="wantedItem">' +
                     i18n.t('stonehearth_ace:ui.game.entities.tooltip_wanted_item_higher' + (hasQuantity ? '_quantity' : ''),
                        {
                           factor: priceMod,
                           quantity: quantity
                        }) + '</div>';
            }
            else if (priceMod < 0) {
               // price is decreased!
               description += '<div class="wantedItem">' +
                     i18n.t('stonehearth_ace:ui.game.entities.tooltip_wanted_item_lower' + (hasQuantity ? '_quantity' : ''),
                        {
                           factor: Math.abs(priceMod),
                           quantity: quantity
                        }) + '</div>';
            }
         }
         else {
            // if it's not wanted and it has a lower price factor, it's an unwanted item the merchant sells
            var priceFactor = self._getBestPriceFactorForItem(item.root_uri, true);
            if (priceFactor < 1) {
               description += '<div class="wantedItem">' +
                     i18n.t('stonehearth_ace:ui.game.entities.tooltip_unwanted_item', {factor: Math.abs(Math.floor((priceFactor - 1) * 100 + 0.5))}) + '</div>';
            }
         }

         var tooltip = App.tooltipHelper.createTooltip(displayNameTranslated, description, extraTip);
         return $(tooltip);
      });
      
   },

   _getEquipmentRolesDiv: function(roles) {
      var rolesArr = roles && stonehearth_ace.findRelevantClassesArray(roles);
      if (rolesArr) {
         var div = '<div class="equipment-roles">';
         rolesArr.forEach(role => {
            if (role.icon) {
               div += `<img src="${role.icon}"/>`;
            }
         });
         div += '</div>';
         return div;
      }

      return '';
   },

   _getEquipmentTypesDiv: function(types) {
      var typesArr = types && stonehearth_ace.getEquipmentTypesArray(types);
      if (typesArr) {
         var div = '<div class="equipment-types">';
         typesArr.forEach(type => {
            if (type.icon) {
               div += `<img src="${type.icon}"/>`;
            }
         });
         div += '</div>';
         return div;
      }

      return '';
   },

   _getEntityData: function(item) {
      if (item.canonical_uri && item.canonical_uri.entity_data) {
         return item.canonical_uri.entity_data;
      }

      if (item.uri.entity_data) {
         return item.uri.entity_data;
      }

      return null;
   },
   
   _getRootUri: function (item) {
      if (!item.uri) return undefined;
      var canonical = item.canonical_uri && item.canonical_uri.__self || item.canonical_uri;
      var uri = canonical ? canonical : item.uri.__self ? item.uri.__self : item.uri;
      return uri;
   },
});
