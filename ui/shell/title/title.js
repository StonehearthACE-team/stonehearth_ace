App.StonehearthTitleScreenView.reopen({
   didInsertElement: function() {
      var self = this;
      self._super();

      App.waitForGameLoad().then(() => {
         radiant.call('stonehearth_ace:get_version_info_command')
            .done(function(response) {
               if (self.isDestroyed || self.isDestroying) {
                  return;
               }

               var branchClass = response.branch.toLocaleLowerCase() == 'unstable' ? 'aceUnstableBranch' : 'aceStableBranch';
               self.set('aceBranchClass', branchClass);
               self.set('aceVersionInfo', response);
               self.set('aceVersion', i18n.t('stonehearth_ace:ui.shell.title_screen.ace_version', response));
            });
      });
   },
});
