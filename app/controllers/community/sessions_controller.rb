module Community
  class SessionsController < Base
    skip_before_action :authenticate!, only: %i[create destroy]
    before_action :validate_cpf_input, only: %i[create]

    def create
      @patient = Patient.find_by(cpf: parse_cpf)

      # New Patient, sent to creation form
      return redirect_to(new_community_patient_path(patient: { cpf: parse_cpf })) unless @patient

      return locked_account! if @patient.locked?

      # Received user from home, show challenge form
      return challenge if session_params[:challenged_mothers_name].blank?

      return failed_login! unless @patient.match_mothers_name?(session_params[:challenged_mothers_name])

      successful_login!
    end

    def destroy
      session.delete(:patient_id)

      redirect_to root_path
    end

    protected

    def validate_cpf_input
      redirect_to root_path, alert: 'CPF inválido' unless CPF.valid?(session_params[:cpf])
    end

    def parse_cpf
      Patient.parse_cpf session_params[:cpf]
    end

    def successful_login!
      @patient.record_successful_login!
      session[:patient_id] = @patient.id
      redirect_to home_community_appointments_path
    end

    def failed_login!
      @patient.record_failed_login!
      return locked_account! if @patient.locked?

      flash.now[:alert] = "Nome incorreto! Você têm mais #{@patient.remaining_login_attempts} tentativa(s), caso " \
                              'acabe o número tentativas esta conta será bloqueada por medida de segurança.'
      challenge
    end

    def locked_account!
      redirect_to root_path, flash: {
        alert: 'CPF bloqueado devido a repetidas tentativas de acesso. ' \
            'Para desbloquear, entre em contato com o Ligue/Web Saúde (telefone abaixo).'
      }
    end

    def session_params
      params.require(:patient).permit(:cpf, :challenged_mothers_name)
    end

    def challenge
      @patient.generate_fake_mothers_list! if @patient.fake_mothers.blank?

      render :challenge
    end
  end
end
