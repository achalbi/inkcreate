class Rack::Attack
  throttle("logins/ip", limit: 10, period: 1.minute) do |request|
    request.ip if request.path == "/api/v1/auth/sign_in" && request.post?
  end

  throttle("uploads/user", limit: 60, period: 1.minute) do |request|
    request.ip if request.path == "/api/v1/upload_urls" && request.post?
  end
end
