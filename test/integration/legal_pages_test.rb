require "test_helper"

class LegalPagesTest < ActionDispatch::IntegrationTest
  test "privacy policy renders publicly" do
    get privacy_policy_path

    assert_response :success
    assert_includes response.body, "Privacy Policy"
    assert_includes response.body, "Google Drive"
    assert_includes response.body, terms_of_service_path
  end

  test "terms of service renders publicly" do
    get terms_of_service_path

    assert_response :success
    assert_includes response.body, "Terms of Service"
    assert_includes response.body, "Acceptable use"
    assert_includes response.body, privacy_policy_path
  end

  test "landing page links to legal pages" do
    get root_path

    assert_response :success
    assert_includes response.body, privacy_policy_path
    assert_includes response.body, terms_of_service_path
  end
end
