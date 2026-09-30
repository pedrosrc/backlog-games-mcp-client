class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Try again later." }

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    return render :new, status: :unprocessable_entity unless @user.valid?(:signup)

    # The backlog lives on the MCP server, so the account is created there first.
    result = mcp.create_user(name: @user.name, email: @user.email_address)
    unless result.success? && result.data&.dig("id")
      @user.errors.add(:base, result.error || "The MCP server did not return a user ID")
      return render :new, status: :unprocessable_entity
    end

    @user.mcp_user_id = result.data["id"]
    if @user.save
      start_new_session_for @user
      redirect_to after_authentication_url, notice: "Welcome, #{@user.name}!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def user_params
      params.expect(user: %i[name email_address password password_confirmation])
    end
end
