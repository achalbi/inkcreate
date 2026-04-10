class DevicesController < BrowserController
  before_action :require_authenticated_user!
  before_action :set_device, only: %i[destroy enable_push disable_push]

  def index
    redirect_to settings_path
  end

  def enable_push
    @device.enable_push!(
      endpoint: push_subscription_params.fetch(:endpoint),
      p256dh_key: push_subscription_params.fetch(:p256dh_key),
      auth_key: push_subscription_params.fetch(:auth_key),
      device_label: push_subscription_params[:label]
    )

    render json: {
      ok: true,
      push_enabled: @device.push_enabled,
      device_label: @device.display_label
    }
  rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid => error
    render json: { ok: false, error: error.message }, status: :unprocessable_entity
  end

  def disable_push
    @device.disable_push!

    respond_to do |format|
      format.html { redirect_to settings_path, notice: "Push notifications disabled for #{@device.display_label}." }
      format.json { render json: { ok: true, push_enabled: false } }
    end
  end

  def destroy
    @device.destroy!
    redirect_to settings_path, notice: "Device removed."
  end

  private

  def set_device
    @device = current_user.devices.find(params[:id])
  end

  def push_subscription_params
    params.require(:device).permit(:label, :endpoint, :p256dh_key, :auth_key)
  end
end
