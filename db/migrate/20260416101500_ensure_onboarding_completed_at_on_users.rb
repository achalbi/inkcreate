class EnsureOnboardingCompletedAtOnUsers < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:users, :onboarding_completed_at)

    add_column :users, :onboarding_completed_at, :datetime
  end
end
