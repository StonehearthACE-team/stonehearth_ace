Handlebars.registerHelper('i18nv', function(i18n_var, options) {
   return i18n.t(Ember.get(options.data.view.content, i18n_var), options);
});