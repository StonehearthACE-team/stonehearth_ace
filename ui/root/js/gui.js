App.guiHelper = {
   _uriTooltips: {},
   _recipeKeyTooltips: {},

   // see _createListValueDiv for value expectations
   // for creating just the list without the anchoring element (e.g., to display on right-click), specify an alternateSelector table
   // the showList function will be added to that table
   createCustomSelector: function (settingId, valuesArray, changedCallback, options) {     
      options = options || {};

      var container = $('<div>')
         .addClass('custom-select');

      var selector;
      if (!options.listOnly) {
         selector = $('<div>')
            .attr('id', settingId)
            .addClass('select-selected');
      }

      var list = $('<div>')
         .attr('setting-id', settingId)
         .addClass('select-items select-hide');

      var showList = function() {
         App.guiHelper._closeListSelectorsExcept(list);
         list.toggleClass('select-hide');
         if (selector) {
            selector.toggleClass('select-arrow-active');
         }
      };

      radiant.each(valuesArray, function (_, value) {
         list.append(App.guiHelper._createListValueDiv(container, value, settingId, changedCallback, options.tooltipFn, showList));
      });

      if (selector) {
         container.append(selector);
         selector.on('click', function() {
            showList();
            return false;
         });
      }
      container.append(list);

      return {
         container: container,
         showList: showList
      };
   },

   getListSelectorValue: function (container) {
      var selector = App.guiHelper._getListSelector(container);
      return selector.attr('data-key');
   },

   _getListSelector: function (container) {
      return container.find('.select-selected');
   },

   _closeListSelectorsExcept: function (list) {
      var doc = $(document);
      
      var elements = doc.find('.select-items');
      if (list) {
         elements = elements.not('[setting-id="' + list.attr('setting-id') + '"]');
      }
      elements.addClass('select-hide');

      elements = doc.find('.select-selected')
      if (list) {
         elements = elements.not('[id="' + list.attr('setting-id') + '"]');
      }
      elements.removeClass('select-arrow-active');
   },

   setListSelectorValue: function (container, value, showListFn) {
      var selector = App.guiHelper._getListSelector(container);

      if (typeof value !== 'object') {
         value = { key: value };
      }
      else if (value == null) {
         value = { key: '[NULL]' };
      }

      if (selector) {
         selector.attr('data-key', value.key);
         selector.html(value.display_name != null ? i18n.t(value.display_name) : value.key);
         App.guiHelper.addTooltip(selector, value.description);
      }

      container.find('.same-as-selected').removeClass('same-as-selected');
      container.find('[data-key="' + value.key + '"]').addClass('same-as-selected');

      if (showListFn) {
         showListFn();
      }
   },

   _createListValueDiv: function (container, value, settingId, changedCallback, tooltipFn, showListFn) {
      // we expect a value object to contain key (value) and optional display_name and description (for tooltip) fields
      // if it's not an object, we'll create a temporary object and assign the value to the key property
      if (typeof value !== 'object') {
         value = { key: value };
      }
      else if (value == null) {
         value = { key: '[NULL]' };
      }

      var div = $('<div>')
         .html(value.display_name != null ? i18n.t(value.display_name) : value.key)
         .attr('data-key', value.key);

      if (value.icon) {
         // if there's an icon, insert it at the beginning of the div
         var img = $('<img>')
            .attr('src', value.icon)
            .addClass('inlineImg');
         div.prepend(img);
      }

      if (tooltipFn) {
         tooltipFn(div, value);
      }
      else if (value.description) {
         App.guiHelper.addTooltip(div, value.description);
      }

      div.on('click', function() {
         // set the current selected value to this value
         App.guiHelper.setListSelectorValue(container, value, showListFn);

         if (changedCallback) {
            changedCallback(settingId, value);
         }

         return false;
      });

      return div;
   },

   addTooltip: function(itemEl, text, title) {
      if (itemEl.hasClass('tooltipstered')) {
         itemEl.tooltipster('destroy');
      }
      if (text && text != '') {
         var tooltip = App.tooltipHelper.createTooltip(title && i18n.t(title) || "", i18n.t(text), "");
         itemEl.tooltipster({ content: $(tooltip) });
      }
   },

   createDynamicTooltip: function($parentEl, selector, contentGenerator, options) {
      if (!$parentEl) return;
      App.guiHelper.removeDynamicTooltip($parentEl, selector);
      $parentEl.on('mouseover.guiHelper.createDynamicTooltip', selector, function() {
         var $element = $(this);
         if ($element.data('tooltipster')) {
            $element.tooltipster('destroy');  // Remove previous tooltip. functionBefore fails to override if specified more than once.
         }

         var tooltipsterArgs = {
            content: ' ',  // Just to force the tooltip to appear. The actual content is created dynamically below.
            functionBefore: function (instance, proceed) {
               if (instance && instance.data('tooltipster')) {
                  var content = contentGenerator ? contentGenerator($element) : instance.attr('title');
                  if (content) {
                     instance.tooltipster('content', content);
                     proceed();
                  }
               }
            },
         };

         if (options) {
            radiant.each(options, function (key, value) {
               tooltipsterArgs[key] = value;
            });
         }

         $element.tooltipster(tooltipsterArgs);
         if (tooltipsterArgs.delay && tooltipsterArgs.delay > 0) {
            var delayTimeout = setTimeout(() => {
               if($element && $element.hasClass('tooltipstered')) {
                  $element.tooltipster('show');
               }
            }, tooltipsterArgs.delay);
            $element.one('mouseout.guiHelper.createDynamicTooltip', function(e) {
               clearTimeout(delayTimeout);
            });
         }
         else {
            $element.tooltipster('show');
         }
      });
   },

   removeDynamicTooltip: function($parentEl, selector) {
      if (!$parentEl) return;
      $parentEl.off('mouseover.guiHelper.createDynamicTooltip', selector);
      var $elements = $parentEl.find(selector);
      $elements.each(function () {
         var $element = $(this);
         if ($element.data('tooltipster')) {
            $element.tooltipster('destroy');
         }
      });
   },

   getTooltipOptions: function(entity) {
      // Only display the stack count for gold in a gold chest.
      var hasOptions = false;
      var itemQuality, maxHealth, menace;
      if (entity['stonehearth:stacks']) {
         hasOptions = true;
      }

      if (entity['stonehearth:attributes']) {
         if (entity['stonehearth:attributes'].max_health) {
            hasOptions = true;
            maxHealth = entity['stonehearth:attributes'].max_health;
         }
         // if (entity['stonehearth:attributes'].menace && entity['stonehearth:siege_weapon']) {
         //    hasOptions = true;
         //    menace = entity['stonehearth:attributes'].menace;
         // }
      }

      if (entity['stonehearth:item_quality'] && entity['stonehearth:item_quality'].quality > 1) {
         hasOptions = true;
         itemQuality = entity['stonehearth:item_quality'].quality;

         // if it's an equipment piece, it grants extra menace based on its item quality
         // TODO: this will change to adjust the rank of weapon/armor buffs
         if (entity['stonehearth:equipment_piece']) {
            // var menaceValues = App.constants.item_quality.bonuses.menace;
            // if (menaceValues[itemQuality]) {
            //    menace = (menace || 0) + menaceValues[itemQuality];
            // }
         }
      }

      if (hasOptions) {
         return {
            self: entity,
            allowUntranslated: false,
            item_quality: itemQuality,
            max_health: maxHealth,
            menace: menace,
            useItemQuality: itemQuality != null,
         };
      }
   },

   createUriTooltip: function(uri, options) {
      var cacheTooltip = this._shouldCacheTooltip(options);
      if (cacheTooltip && this._uriTooltips[uri]) {
         return this._uriTooltips[uri];
      }

      var catalogData = App.catalog.getCatalogData(uri);
      if (!catalogData) return;

      options = options || { allowUntranslated: false };
      options.show_appeal = options.show_appeal !== false;
      options.show_net_worth = options.show_net_worth !== false;
      options.show_fuel_amount = options.show_fuel_amount !== false;

      if (options.recipe_key && this._recipeKeyTooltips[options.recipe_key]) {
         return this._recipeKeyTooltips[options.recipe_key];
      }

      var itemQuality = options.item_quality || 1;

      var title = options.display_name || catalogData.display_name;
      title = title && i18n.t(title, options);
      if (catalogData.deprecated) {
         title = '<span class="item-tooltip-title item-deprecated">' + title + '</span>';
      } else if (itemQuality > 1) {
         title = '<span class="item-tooltip-title item-quality-' + options.item_quality + '">' + title + '</span>';
      }

      var detail = '';
      // TODO: show buffs?

      if (catalogData.food_satisfaction) {
         detail += this._getSatisfactionDiv('food', App.constants.food_satisfaction_thresholds, catalogData.food_satisfaction, catalogData.food_servings);
      }
      if (catalogData.drink_satisfaction) {
         detail += this._getSatisfactionDiv('drink', App.constants.drink_satisfaction_thresholds, catalogData.drink_satisfaction, catalogData.drink_servings);
      }

      // collision size
      if (catalogData.collision_size) {
         detail += `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_size_header')}</span>` +
                     `${i18n.t('stonehearth_ace:ui.game.entities.tooltip_size', catalogData.collision_size)}</div>`;
      }

      // max length
      if (catalogData.max_length) {
         detail += `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_max_length')}</span>` +
                     `<span class="value">${catalogData.max_length}</span></div>`;
      }

      // storage capacity
      if (catalogData.storage_capacity) {
         detail += `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_storage_capacity')}</span>` +
                     `<span class="value">${catalogData.storage_capacity}</span></div>`;
      }
      
      // if it's a consumer entity, it has fuel capacity instead
      if (catalogData.fuel_capacity) {
         detail += `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_fuel_capacity')}</span>` +
                     `<span class="value">${catalogData.fuel_capacity}</span></div>`;
      }

      if (catalogData.warmth_radius) {
         detail += `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_warmth_radius')}</span>` +
                  `<span class="value">${catalogData.warmth_radius}</span></div>`;
      }

      if (catalogData.sight_range) {
         detail += `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_sight_range')}</span>` +
                  `<span class="value">${catalogData.sight_range}</span></div>`;
      }

      var equipmentRequirements = '';
      if (catalogData.equipment_roles) {
         var equipmentRoles = this._getEquipmentRolesDiv(catalogData.equipment_roles);
         equipmentRequirements += `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_equipment_requirement')}</span>${equipmentRoles}`;
         if (catalogData.equipment_required_level) {
            equipmentRequirements += i18n.t('stonehearth:ui.game.show_workshop.level_requirement_level') +
               `<span class="value">${catalogData.equipment_required_level}</span>`;
         }
         equipmentRequirements += '</div>';
      }
      if (catalogData.equipment_types) {
         var equipmentTypes = this._getEquipmentTypesDiv(catalogData.equipment_types);
         equipmentRequirements += `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_equipment_type')}</span>${equipmentTypes}</div>`;
      }

      if (catalogData.equipment_ilevel) {
         equipmentRequirements += `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_equipment_ilevel')}</span>` +
                  `<span class="value">${catalogData.equipment_ilevel * 10}</span></div>`;
      }

      if (equipmentRequirements != '') {
         detail += equipmentRequirements;
      }

      var combat_info = "";
      if (catalogData.combat_damage) {
         combat_info += '<div class="stat"><span class="header">' + i18n.t('stonehearth:ui.game.entities.tooltip_combat_base_damage') + '</span>' +
                     '<span class="combatValue">+' + catalogData.combat_damage + '</span></div>';
      }

      if (catalogData.combat_range) {
         combat_info += '<div class="stat"><span class="header">' + i18n.t('stonehearth_ace:ui.game.entities.tooltip_combat_range') + '</span>' +
                     '<span class="combatValue">+' + catalogData.combat_range + '</span></div>';
      }
      if (catalogData.combat_reach) {
         combat_info += '<div class="stat"><span class="header">' + i18n.t('stonehearth_ace:ui.game.entities.tooltip_combat_reach') + '</span>' +
                     '<span class="combatValue">+' + catalogData.combat_reach + '</span></div>';
      }

      if (catalogData.combat_armor) {
         combat_info += '<div class="stat"><span class="header">' + i18n.t('stonehearth:ui.game.entities.tooltip_combat_base_damage_reduction') + '</span>' +
                     '<span class="combatValue">+' + catalogData.combat_armor + '</span></div>'
      }

      var max_health = options.max_health || catalogData.max_health;
      if (max_health) {
         var maxHealthDiv = `<span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_max_health')}</span>` +
               `<span class="combatValue">${catalogData.max_health}</span>`;
         var compare_max_health = catalogData.max_health;
         if (compare_max_health && max_health != compare_max_health) {
            var diff = max_health - compare_max_health;
            var diffType = diff > 0 ? 'higherValue' : 'lowerValue';
            maxHealthDiv += ` (<span class="${diffType}">${(diff > 0 ? '+' : '') + diff}</span>)`;
         }
         combat_info += `<div class="stat">${maxHealthDiv}</div>`;
      }

      var menace = options.menace || catalogData.menace;
      if (menace) {
         var menaceDiv = `<span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_menace')}</span>` +
               `<span class="combatValue">${menace}</span>`;
         // var compare_menace = catalogData.menace;
         // if (compare_menace && menace != compare_menace) {
         //    var diff = menace - compare_menace;
         //    var diffType = diff > 0 ? 'higherValue' : 'lowerValue';
         //    menaceDiv += ` (<span class="${diffType}">${(diff > 0 ? '+' : '') + diff}</span>)`;
         // }
         combat_info += `<div class="stat">${menaceDiv}</div>`;
      }

      if (combat_info != "") {
         detail += combat_info;
      }

      if (options.moreDetails) {
         detail += options.moreDetails;
      }

      if (detail != '') {
         detail = '<div class="details">' + detail + '</div>';
      }
      
      var description =  options.description || catalogData.description;
      if (description) {
         detail = `<span class='description'>${i18n.t(description, options)}</span>` + detail;
      }

      var netWorthAppeal = '';
      var net_worth = options.net_worth;
      var showDiff = true;
      if (!net_worth && catalogData.net_worth && options.show_net_worth) {
         if (itemQuality > 1) {
            net_worth = radiant.applyItemQualityBonus('net_worth', catalogData.net_worth, itemQuality);
         }
         else {
            net_worth = catalogData.net_worth;
            // special case for chest of gold coins
            // TODO: maybe special case for other things with stacks?
            if (uri == 'stonehearth:loot:gold') {
               showDiff = false;
               var stacks = options.self && options.self['stonehearth:stacks'];
               net_worth *= (stacks && stacks.stacks || 1);
            }
         }
      }
      if (options.net_worth || (options.show_net_worth && net_worth)) {
         var netWorthDiv = `<span class="value">${net_worth}</span>`;
         var compare_net_worth = catalogData.net_worth;
         if (compare_net_worth && options.useItemQuality && itemQuality > 1) {
            compare_net_worth = radiant.applyItemQualityBonus('net_worth', compare_net_worth, itemQuality);
         }
         if (showDiff && compare_net_worth && net_worth != compare_net_worth) {
            var diff = net_worth - compare_net_worth;
            var diffType = (options.invertNetWorthDiffColor ? diff < 0 : diff > 0) ? 'higherValue' : 'lowerValue';
            netWorthDiv += ` (<span class="${diffType}">${(diff > 0 ? '+' : '') + diff}</span>)`;
         }
         netWorthAppeal += `<img class="imgHeader netWorth"/>${netWorthDiv}<span class="spacer"/>`;
      }

      var appeal = options.appeal;
      if (!appeal && catalogData.appeal && options.show_appeal) {
         if (itemQuality > 1) {
            appeal = radiant.applyItemQualityBonus('appeal', catalogData.appeal, itemQuality);
         }
         else {
            appeal = catalogData.appeal;
         }
      }
      if (options.appeal || (options.show_appeal && appeal)) {
         var appealDiv = `<span class="value">${appeal}</span>`;
         var compare_appeal = catalogData.appeal;
         if (compare_appeal && options.useItemQuality && itemQuality > 1) {
            compare_appeal = radiant.applyItemQualityBonus('appeal', compare_appeal, itemQuality);
         }
         if (compare_appeal && appeal != compare_appeal) {
            var diff = appeal - compare_appeal;
            appealDiv += ` (<span class="${diff > 0 ? 'higherValue' : 'lowerValue'}">${(diff > 0 ? '+' : '') + diff}</span>)`;
         }
         netWorthAppeal += `<img class="imgHeader appeal"/>${appealDiv}`;
      }

      if (options.fuel_amount || (catalogData.fuel_amount && options.show_fuel_amount)) {
         var fuel_amount = options.fuel_amount || catalogData.fuel_amount;
         netWorthAppeal += `<span class="spacer"/><img class="imgHeader fuelAmount"/><span class="value">${fuel_amount}</span>`;
      }

      if (netWorthAppeal != '') {
         detail += `<div class="details"><div class="stat">${netWorthAppeal}</div></div>`
      }

      if (catalogData.deprecated) {
         detail += `<div class="item-deprecated-tooltip">${i18n.t('stonehearth:ui.game.entities.tooltip_deprecated')}</div>`;
      }

      if (options.recipe_key) {
         // if it's a recipe, add information for interacting with the crafting ui
         detail += `<div class="verticalSpacer faded">${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_recipe_list_queueing')}</div>`;
      }

      var tooltip = App.tooltipHelper.createTooltip(title, detail);
      if (cacheTooltip) {
         this._uriTooltips[uri] = tooltip;
      }
      else if (options.recipe_key) {
         this._recipeKeyTooltips[options.recipe_key] = tooltip;
      }

      return tooltip;
   },

   _shouldCacheTooltip: function(options) {
      if (!options) {
         return true;
      }
   },

   _getEquipmentRolesDiv: function(roles) {
      var rolesArr = roles && stonehearth_ace.findRelevantClassesArray(roles);
      if (rolesArr) {
         var isFirst = true;
         var div = ''; // '<div class="equipment-roles">';
         rolesArr.forEach(role => {
            if (!isFirst) {
               div += ', ';
            }
            if (role.icon) {
               div += `<img class="inlineImg" src="${role.icon}"/>`;
            }
            div += `<span class="value">${i18n.t(role.readableName)}</span>`;
            isFirst = false;
         });
         //div += '</div>';
         return div;
      }

      return '';
   },

   _getEquipmentTypesDiv: function(types) {
      var typesArr = types && stonehearth_ace.getEquipmentTypesArray(types);
      if (typesArr) {
         var isFirst = true;
         var div = ''; // '<div class="equipment-types">';
         typesArr.forEach(type => {
            if (!isFirst) {
               div += ', ';
            }
            if (type.icon) {
               div += `<img class="inlineImg" src="${type.icon}"/>`;
            }
            div += `<span class="value">${i18n.t(type.name)}</span>`;
            isFirst = false;
         });
         //div += '</div>';
         return div;
      }

      return '';
   },

   _getSatisfactionDiv: function(satisfactionType, thresholds, satisfaction, servings) {
      var satisfactionLevel = stonehearth_ace.getSatisfactionLevel(thresholds, satisfaction)
      if (satisfactionLevel && servings) {
         var singleServing = servings == 1 ? '_single' : '';
         return `<div class="stat"><img class="imgHeader satisfaction ${satisfactionType} ${satisfactionLevel}"/>` +
                  i18n.t(`stonehearth_ace:ui.game.entities.tooltip_satisfaction.${satisfactionType}.${satisfactionLevel}${singleServing}`, {servings: servings}) +
                  '</div>';
      }
   }
};

$(document).on('click', function() {
   App.guiHelper._closeListSelectorsExcept();
})
