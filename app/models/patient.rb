class Patient < ApplicationRecord
  devise :database_authenticatable, :registerable, :rememberable, authentication_keys: [:cpf]

  MAX_LOGIN_ATTEMPTS = 2

  CONDITIONS = {
    'População em geral com 70 anos ou mais' => ->(patient) { patient.age >= 70 },
    # 'Trabalhador(a) da Saúde que possua vínculo ativo em alguma unidade registrada no CNES' => ->(patient) { patient.in_group?('Trabalhador(a) da Saúde') },
    # 'Paciente de teste' => ->(patient) { patient.cpf == ENV['ROOT_PATIENT_CPF'] },
    # 'Maiores de 60 anos institucionalizadas' => ->(patient) { patient.age >= 60 && patient.in_group?('Institucionalizado(a)') },
    # 'População Indígena' => ->(patient) { patient.in_group?('Indígena') },
  }

  has_many :appointments, dependent: :destroy
  has_and_belongs_to_many :groups
  belongs_to :main_ubs, class_name: 'Ubs'
  belongs_to :last_appointment, class_name: 'Appointment', optional: true

  validates :name, presence: true
  validates :cpf, presence: true, uniqueness: true, cpf_format: true
  validates :mother_name, presence: true
  validates :birth_date, presence: true
  validates :phone, presence: true, phone_format: true
  validates :neighborhood, presence: true

  validate :valid_birth_date

  # Only set new main_ubs if it is empty or there was a change to the neighborhood
  before_validation :set_main_ubs!, if: proc { |r| r.neighborhood_changed? || r.main_ubs_id.blank? }

  scope :bedridden, -> { where(bedridden: true) }

  # TODO: remove `chronic` field from schema
  enum target_audience: [:kid, :elderly, :chronic, :disabled, :pregnant, :postpartum, :teacher, :over_55, :without_target]

  def current_appointment
    appointments.order(:start).select(&:active?).last
  end

  def first_appointment
    appointments.where.not(check_out: nil).order(:start).first
  end

  def can_see_appointment?
    return true if has_future_appointments?
  end

  def can_schedule?
    CONDITIONS.values.any? do |condition|
      condition.call(self)
    end
  end

  def has_future_appointments?
    appointments
      .where('start >= ? AND active = TRUE', Time.zone.now)
      .exists?
  end

  def in_group?(name)
    groups.map(&:name).include?(name)
  end

  def set_main_ubs!
    self.main_ubs =
      # samples an active ubs near the patient neighborhood
      Neighborhood.find_by(name: neighborhood)&.active_ubs&.sample ||
      # samples any active ubs
      Ubs.active.sample ||
      # samples any inactive ubs
      Ubs.all.sample
  end

  def email_required?
    false
  end

  def email_changed?
    false
  end

  def increase_login_attempts
    update!(login_attempts: login_attempts + 1)
  end

  def remaining_attempts
    MAX_LOGIN_ATTEMPTS - login_attempts
  end

  def blocked?
    login_attempts >= MAX_LOGIN_ATTEMPTS
  end

  def bedridden?
    bedridden == true
  end

  def unblock!
    update!(login_attempts: 0)
  end

  def encrypted_password
    ''
  end

  def age
    ((Time.zone.now - birth_date.to_time) / 1.year.seconds).floor
  end

  def vaccinated?
    last_appointment&.second_dose && last_appointment&.check_out.present?
  end

  private

  def valid_birth_date
    Date.parse(birth_date)
  rescue ArgumentError
    errors.add(:birth_date, :invalid)
  end
end
