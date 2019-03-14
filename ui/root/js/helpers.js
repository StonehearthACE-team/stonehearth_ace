// need to add support for titles to name localization
i18n.addPostProcessor("localizeEntityName", function(value, key, isFound, opts) {
   //i18n(__i18n_data.entity_display_name__, {\"self.stonehearth:unit_info.custom_name\":\"__i18n_data.entity_custom_name__\"})

   var nameHelperPrefix = '[name(';
   var nameHelperSuffix = ')]';
   var replacementCounter = 0;
   var maxRecursion = 4;

   opts.postProcess = null;

   // spiegg's solution here: https://stackoverflow.com/questions/6491463/accessing-nested-javascript-objects-with-string-key
   function interpretPropertyString(s, obj) {
      var properties = Array.isArray(s) ? s : s.split('.')
      return properties.reduce((prev, curr) => prev && prev[curr], obj)
   }

   function localizeName(translated, options) {
     while (translated.indexOf(nameHelperPrefix) != -1) {
         replacementCounter++;
         if (replacementCounter > maxRecursion) {
            break;
         } // safety net for too much recursion
         var indexOfOpening = translated.lastIndexOf(nameHelperPrefix);
         var indexOfEndOfClosing = translated.indexOf(nameHelperSuffix, indexOfOpening) + nameHelperSuffix.length;
         var token = translated.substring(indexOfOpening, indexOfEndOfClosing);
         var tokenWithoutSymbols = token.replace(nameHelperPrefix, '').replace(nameHelperSuffix, '');

         if (indexOfEndOfClosing <= indexOfOpening) {
             f.error('there is a missing closing in following translation value', translated);
             return '';
         }

         // if [entity]_custom_name doesn't work, assume it's a full entity passed to us
         var customNameKey = i18n.options.interpolationPrefix + tokenWithoutSymbols + "_custom_name" + i18n.options.interpolationSuffix;
         var customName = i18n.applyReplacement(customNameKey, opts);
         var isFullEntity = false;
         if (customName == customNameKey) {
            customNameKey = i18n.options.interpolationPrefix + tokenWithoutSymbols + ".stonehearth:unit_info.custom_name" + i18n.options.interpolationSuffix;
            customName = i18n.applyReplacement(customNameKey, opts);
            isFullEntity = true;
         }

         var newToken = i18n.options.interpolationPrefix + tokenWithoutSymbols + (isFullEntity ? ".stonehearth:unit_info.display_name" : "_display_name") + i18n.options.interpolationSuffix;
         var replacedToken = i18n.applyReplacement(newToken, opts);

         var tokenData = interpretPropertyString(tokenWithoutSymbols, opts);
         opts['self'] = {};
         opts.self['stonehearth:unit_info'] = tokenData && tokenData['stonehearth:unit_info'];
         if (!opts.self['stonehearth:unit_info']) {
            opts.self['stonehearth:unit_info'] = {
               'custom_name': customName,
               'custom_data': interpretPropertyString(tokenWithoutSymbols + '_custom_data', opts) || {}
            };
         }
         opts.defaultValue = i18n.t("stonehearth:ui.game.entities.unknown_name");
         var translatedToken = i18n.t(replacedToken, opts);
         if (options.escapeHTML) {
            translatedToken = Ember.Handlebars.Utils.escapeExpression(translatedToken);
         }
         translated = translated.replace(token, translatedToken);
     }
     return translated;
   }

   if (value.indexOf("[name(") >= 0) {
      var newValue = localizeName(value, opts);
      newValue = i18n.applyReplacement(newValue, opts);
      return newValue;
   }

   if (value == key && !isFound) {
      return undefined;
   }


   return value;
});