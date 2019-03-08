App.guiHelper = {

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
   }

};

$(document).on('click', function() {
   App.guiHelper._closeListSelectorsExcept();
})
