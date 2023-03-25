App.guiHelper = {
   _uriTooltips: {},

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
            var delayTimeout = setTimeout(() => $element.tooltipster('show'), tooltipsterArgs.delay);
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

   getUriTooltip: function(uri, options) {
      if (!options && this._uriTooltips[uri]) {
         return $(this._uriTooltips[uri]);
      }

      var catalogData = App.catalog.getCatalogData(uri);
      if (!catalogData) return;

      if (!options) {
         options = {
            show_appeal: true,
            show_net_worth: true,
         };
      }

      var title = catalogData.display_name && i18n.t(catalogData.display_name, options);
      if (options.item_quality && options.item_quality > 1) {
         title = '<span class="item-tooltip-title item-quality-' + options.item_quality + '">' + title + '</span>';
      }
      var description = catalogData.description && `<span class='description'>${i18n.t(catalogData.description, options)}</span>`;
      var extra = '';
      var hasDetail = false;

      var appeal = options.appeal || catalogData.appeal;
      if (options.appeal || (options.show_appeal && appeal)) {
         extra += `<div class="appeal">${catalogData.appeal}</div>`;
      }

      var net_worth = options.net_worth || catalogData.net_worth
      if (options.net_worth || (options.show_net_worth && net_worth)) {
         extra += `<div class="netWorth">${net_worth}</div>`;
      }

      var detail = '<div class="details">';
      // TODO: show buffs? quality?

      var satisfactionLevel, servings;
      if (satisfactionLevel == null || servings == null) {
         if (catalogData.food_satisfaction) {
            satisfactionLevel = 'food.' + stonehearth_ace.getSatisfactionLevel(App.constants.food_satisfaction_thresholds, catalogData.food_satisfaction);
            servings = catalogData.food_servings;
         }
         else if (catalogData.drink_satisfaction) {
            satisfactionLevel = 'drink.' + stonehearth_ace.getSatisfactionLevel(App.constants.drink_satisfaction_thresholds, catalogData.drink_satisfaction);
            servings = catalogData.drink_servings;
         }
      }

      if (satisfactionLevel && servings) {
         hasDetail = true;
         detail += '<div class="stat">' +
                  i18n.t(`stonehearth_ace:ui.game.generic_tooltips.satisfaction.${satisfactionLevel}`, {servings: servings}) +
                  '</div>';
      }

      var equipmentRequirements = '';
      if (catalogData.equipment_roles) {
         var allowedClasses = stonehearth_ace.findRelevantClassesArray(catalogData.equipment_roles);
         equipmentRequirements += i18n.t('stonehearth_ace:ui.game.generic_tooltips.equipment_description',
                                 { class_list: radiant.getClassString(allowedClasses) });
         if (catalogData.equipment_required_level) {
            equipmentRequirements += i18n.t('stonehearth_ace:ui.game.generic_tooltips.level_description', { level_req: catalogData.equipment_required_level });
         }
      }
      if (catalogData.equipment_types) {
         var equipmentTypes = stonehearth_ace.getEquipmentTypesArray(catalogData.equipment_types);
         equipmentRequirements += '<br>' + i18n.t('stonehearth_ace:ui.game.generic_tooltips.equipment_types_description',
                                          { i18n_data: { types: stonehearth_ace.getEquipmentTypesString(equipmentTypes) } });
      }

      if (equipmentRequirements != '') {
         hasDetail = true;
         detail += `<div class='stat'>${equipmentRequirements}</div>`;
      }

      if (catalogData.combat_damage) {
         hasDetail = true;
         detail += `<div class="stat">${i18n.t('stonehearth_ace:ui.game.generic_tooltips.damage', {damage: catalogData.combat_damage})}</div>`;
      }
      if (catalogData.combat_armor) {
         hasDetail = true;
         detail += `<div class="stat">${i18n.t('stonehearth_ace:ui.game.generic_tooltips.armor', {armor: catalogData.combat_armor})}</div>`;
      }

      detail += '</div>';

      var tooltip = App.tooltipHelper.createTooltip(title, description + (hasDetail ? detail : ''), extra == '' ? null : extra);
      this._uriTooltips[uri] = tooltip;

      return $(tooltip);
   }
};

$(document).on('click', function() {
   App.guiHelper._closeListSelectorsExcept();
})
