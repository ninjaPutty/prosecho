module DirectoryPolicy
  def confirm_directory_policy
    Access::Provisioner.new(actor: users(:administrator)).save_data_policy(revision: "new",
      attributes: {status: "confirmed", profile_retention_days: 90,
                   history_retention_days: 365, log_retention_days: 90, backup_retention_days: 30,
                   address_handling: "Omit missing or ambiguous homes.",
                   household_handling: "Report only authorized membership facts."})
  end
end
