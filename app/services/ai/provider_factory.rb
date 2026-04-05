module Ai
  class ProviderFactory
    def self.build(_provider_name = nil)
      NullProvider.new
    end
  end
end
