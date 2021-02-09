class ApplicationController < ActionController::Base
  # before_action :set_raven_context
  before_action :update_allowed_parameters, if: :devise_controller?

  def after_sign_in_path_for(resource)
    if resource.is_a?(User)
      ubs_index_path
    elsif resource.is_a?(Admin)
      admin_index_path
    elsif resource.is_a?(Patient)
      return index_bedridden_path if resource.bedridden?

      index_time_slot_path
    else
      root_path
    end
  end

  # private

  # def set_raven_context
  #   if (current_user.present?)
  #     user_identifier = "Operator"
  #     user_identifier_id = current_user.id
  #   elsif (current_patient.present?)
  #     user_identifier = "Patient"
  #     user_identifier_id = current_patient.id
  #   else
  #     user_identifier = "Not logged yet"
  #     user_identifier_id = nil
  #   end

	#     Raven.user_context(id: user_identifier_id, user: user_identifier)
	#     Raven.extra_context(params: params.to_unsafe_h, url: request.url)
  # end

  def update_allowed_parameters
    devise_parameter_sanitizer.permit(:sign_in) { |u| u.permit(:username, :email, :password, :remember_me)}
    devise_parameter_sanitizer.permit(:account_update) { |u| u.permit(:username, :email, :password, :current_password, :remember_me)}
  end
  
end
