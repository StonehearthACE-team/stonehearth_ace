Handlebars.registerHelper('i18nv', function(i18n_var, options) {
   var obj = options.data.view.content;
   if (!obj) {
      obj = options.data.view;
   }
   return i18n.t(Ember.get(obj, i18n_var), options);
});