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
      showZeroes: false,
      skipCategories: false,
      sortField: 'display_name'
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
      App.tooltipHelper.removeDynamicTooltip(this.element);
      this.palette.off('click', '.item');
   },

   updateItems: function(itemMap) {
      var self = this;

      // Start off with all items marked as not updated.
      var updated = {
         items: {},
         categories: {},
      };

      // Convert item entries for display.
      var arr = radiant.map_to_array(itemMap, function(k, v){
         var uri = self._getUri(v);
         if (uri) {
            var catalogData = App.catalog.getCatalogData(uri);
            if (catalogData) {
               v.display_name = catalogData.display_name;
               v.description = catalogData.description;
               v.category = catalogData.category;
               v.icon = catalogData.icon;
               v.item_quality = v.item_quality || 1;
               v.deprecated = catalogData.deprecated;
               return v;
            }
         }
         return false;  // Skip items with no URI ot catalog data.
      });

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

      // Go through each item and update the corresponding DOM element for it.
      radiant.each(arr, function(i, item) {
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
      })

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
   },

   _findCategory: function(item) {
      var selector = "[category='" + item.category + "']";
      var match = this.palette.find(selector)[0];

      if (match) {
         return $(match);
      }
   },

   _addCategoryForItem: function(item) {
      var category = $('<div>')
         .addClass('category')
         .attr('category', item.category);

      // new title element for the category
      var categoryDisplayName = i18n.t('stonehearth:ui.game.entities.item_categories.' + item.category);
      if (!categoryDisplayName) {
         console.log("No category display name found for item category " + item.category);
         categoryDisplayName = item.category;
      }

      $('<h2>')
         .html(categoryDisplayName)
         .appendTo(category);

      // the category container element that items are inserted into
      $('<div>')
         .addClass('downSection')
         .appendTo(category);

      category.appendTo(this.palette);

      return category;
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
            var stacksComponent = individualItem['stonehearth:stacks'];
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

         var tooltip = App.tooltipHelper.createTooltip(displayNameTranslated, description, extraTip);
         return $(tooltip);
      });
      
   },

   _getEntityData: function(item) {
      if (item.canonical_uri && item.canonical_uri.entity_data) {
         return item.canonical_uri.entity_data;
      }

      if (item.uri.entity_data) {
         return item.uri.entity_data;
      }

      return null;
   }
});
