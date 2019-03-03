App.guiHelper = {

   // see _createListValueDiv for value expectations
   createCustomSelector: function (settingId, valuesArray, changedCallback) {
      var container = $('<div>')
         .addClass('custom-select');

      var selector = $('<div>')
         .attr('id', settingId)
         .addClass('select-selected');

      var list = $('<div>')
         .attr('setting-id', settingId)
         .addClass('select-items select-hide');

      radiant.each(valuesArray, function (_, value) {
         list.append(App.guiHelper._createListValueDiv(container, value, settingId, changedCallback));
      });

      container.append(selector);
      container.append(list);

      selector.on('click', function() {
         App.guiHelper._closeListSelectorsExcept(list);
         list.toggleClass('select-hide');
         selector.toggleClass('select-arrow-active');
         return false;
      });

      return container;
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

   setListSelectorValue: function (container, value, doClick) {
      var selector = App.guiHelper._getListSelector(container);

      if (typeof value !== 'object') {
         value = { key: value };
      }
      else if (value == null) {
         value = { key: '[NULL]' };
      }

      selector.attr('data-key', value.key);
      selector.html(value.display_name != null ? i18n.t(value.display_name) : value.key);
      App.guiHelper.addTooltip(selector, value.description);

      container.find('.same-as-selected').removeClass('same-as-selected');
      container.find('[data-key="' + value.key + '"]').addClass('same-as-selected');

      if (doClick) {
         selector.click();
      }
   },

   _createListValueDiv: function (container, value, settingId, changedCallback) {
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

      if (value.description) {
         App.guiHelper.addTooltip(div, value.description);
      }

      div.on('click', function() {
         // set the current selected value to this value
         App.guiHelper.setListSelectorValue(container, value, true);

         if (changedCallback) {
            changedCallback(settingId, value.key);
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
   }

};

$(document).on('click', function() {
   App.guiHelper._closeListSelectorsExcept();
})
