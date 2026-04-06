require "test_helper"

class DriveClientFactoryTest < ActiveSupport::TestCase
  FakeDriveService = Struct.new(:authorization)

  class FakeCredentials
    attr_reader :access_token, :refresh_token, :expires_at

    def initialize(access_token:, refresh_token:, expires_at:, expiring:)
      @access_token = access_token
      @refresh_token = refresh_token
      @expires_at = expires_at
      @expiring = expiring
    end

    def expires_within?(_seconds)
      @expiring
    end

    def refresh!
      @access_token = "fresh-access-token"
      @refresh_token = "fresh-refresh-token"
      @expires_at = 2.hours.from_now
    end
  end

  def build_user(email:)
    User.create!(
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
  end

  test "refreshes expired drive credentials before building the client" do
    user = build_user(email: "drive-client-factory@example.com")
    user.update!(
      google_drive_access_token: "expired-access-token",
      google_drive_refresh_token: "refresh-token",
      google_drive_token_expires_at: 2.hours.ago,
      google_drive_connected_at: Time.current
    )

    credentials = FakeCredentials.new(
      access_token: user.google_drive_access_token,
      refresh_token: user.google_drive_refresh_token,
      expires_at: user.google_drive_token_expires_at,
      expiring: true
    )
    drive_service = FakeDriveService.new

    Google::Auth::UserRefreshCredentials.stub(:new, credentials) do
      Google::Apis::DriveV3::DriveService.stub(:new, drive_service) do
        service = Drive::ClientFactory.build(user: user)

        assert_same drive_service, service
        assert_same credentials, service.authorization
      end
    end

    user.reload

    assert_equal "fresh-access-token", user.google_drive_access_token
    assert_equal "fresh-refresh-token", user.google_drive_refresh_token
    assert user.google_drive_token_expires_at > Time.current
  end

  test "refreshes drive credentials when expiry is missing" do
    user = build_user(email: "drive-client-factory-no-expiry@example.com")
    user.update!(
      google_drive_access_token: "stale-access-token",
      google_drive_refresh_token: "refresh-token",
      google_drive_token_expires_at: nil,
      google_drive_connected_at: Time.current
    )

    credentials = FakeCredentials.new(
      access_token: user.google_drive_access_token,
      refresh_token: user.google_drive_refresh_token,
      expires_at: user.google_drive_token_expires_at,
      expiring: false
    )
    drive_service = FakeDriveService.new

    Google::Auth::UserRefreshCredentials.stub(:new, credentials) do
      Google::Apis::DriveV3::DriveService.stub(:new, drive_service) do
        service = Drive::ClientFactory.build(user: user)

        assert_same drive_service, service
        assert_same credentials, service.authorization
      end
    end

    user.reload

    assert_equal "fresh-access-token", user.google_drive_access_token
    assert_equal "fresh-refresh-token", user.google_drive_refresh_token
    assert user.google_drive_token_expires_at > Time.current
  end
end
