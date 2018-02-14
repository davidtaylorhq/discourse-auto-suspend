# name: discourse-auto-suspend
# about: Automatically suspends inactive users after a defined time period
# version: 0.0.1
# authors: David Taylor
# url: https://github.com/davidtaylorhq/discourse-auto-suspend

enabled_site_setting :auto_suspend_enabled

PLUGIN_NAME ||= 'discourse_auto_suspend'.freeze

after_initialize do
  module ::DiscourseAutoSuspend
    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscourseAutoSuspend
    end
  end

  module ::Jobs
    class AutoSuspendUsers < Jobs::Scheduled
      every 1.day

      def execute(args)
        return if !SiteSetting.auto_suspend_enabled?

        auto_suspend_days = SiteSetting.auto_suspend_after_days.days.ago
        to_suspend = User.where("last_seen_at IS NULL OR last_seen_at < ? AND created_at < ?", auto_suspend_days, auto_suspend_days)
                         .where('suspended_till IS NULL OR suspended_till < ?', Time.zone.now)
                         .real

        for user in to_suspend do
          safe_groups = SiteSetting.auto_suspend_safe_groups
          user_is_safe = user.groups.any?{|g| safe_groups.include? g.name}

          if not user_is_safe then
            user.suspended_at = Time.now
            user.suspended_till = SiteSetting.auto_suspend_for_years.years.from_now
            ban_reason = I18n.t("discourse_auto_suspend.suspend-reason")

            if user.save
              StaffActionLogger.new(Discourse.system_user).log_user_suspend(user, ban_reason)
            end
          end
        end
      end
    end
  end
end
