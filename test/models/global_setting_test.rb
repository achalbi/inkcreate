require "test_helper"

class GlobalSettingTest < ActiveSupport::TestCase
  test "password auth stays enabled in development when google auth is configured" do
    GlobalSetting.instance.update!(password_auth_enabled: false)

    GlobalSetting.stub(:google_auth_configured?, true) do
      GlobalSetting.stub(:development_env?, true) do
        assert GlobalSetting.password_auth_forced_on?
        assert GlobalSetting.password_auth_enabled?
      end
    end
  end

  test "password auth still respects the toggle outside development when google auth is configured" do
    GlobalSetting.instance.update!(password_auth_enabled: false)

    GlobalSetting.stub(:google_auth_configured?, true) do
      GlobalSetting.stub(:development_env?, false) do
        assert_not GlobalSetting.password_auth_forced_on?
        assert_not GlobalSetting.password_auth_enabled?
      end
    end
  end
end
