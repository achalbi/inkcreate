module Ocr
  ProviderResult = Data.define(:raw_text, :cleaned_text, :mean_confidence, :language, :metadata)
end
