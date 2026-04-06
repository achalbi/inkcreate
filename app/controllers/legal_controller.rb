class LegalController < BrowserController
  EFFECTIVE_DATE = Date.new(2026, 4, 6).freeze

  helper_method :legal_effective_date

  def privacy_policy; end

  def terms_of_service; end

  private

  def legal_effective_date
    EFFECTIVE_DATE.strftime("%B %-d, %Y")
  end
end
