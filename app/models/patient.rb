class Patient < ApplicationRecord
  MAX_LOGIN_ATTEMPTS = 3

  CONDITIONS = {
    'População em geral com 70 anos ou mais' => ->(patient) { patient.age >= 70 }
    # 'Trabalhador(a) da Saúde que possua vínculo ativo em alguma unidade registrada no CNES' => ->(patient) { patient.in_group?('Trabalhador(a) da Saúde') },
    # 'Paciente de teste' => ->(patient) { patient.cpf == ENV['ROOT_PATIENT_CPF'] },
    # 'Maiores de 60 anos institucionalizadas' => ->(patient) { patient.age >= 60 && patient.in_group?('Institucionalizado(a)') },
    # 'População Indígena' => ->(patient) { patient.in_group?('Indígena') },
  }.freeze

  has_many :appointments, dependent: :destroy do
    # Returns the last available active appointment
    def current
      order(:start).active.includes(:ubs).last
    end
  end
  has_and_belongs_to_many :groups
  belongs_to :main_ubs, class_name: 'Ubs'

  validates :cpf, presence: true, uniqueness: true, cpf_format: true
  validates :name, presence: true
  validates :birth_date, presence: true
  validates :mother_name, presence: true
  validates :phone, presence: true, phone_format: true
  validates :neighborhood, presence: true
  validates :place_number, presence: true
  validates :public_place, presence: true

  validate :valid_birth_date

  # Only set new main_ubs if it is empty or there was a change to the neighborhood
  before_validation :set_main_ubs!, if: proc { |r| r.neighborhood_changed? || r.main_ubs_id.blank? }

  scope :bedridden, -> { where(bedridden: true) }

  scope :locked, -> { where(arel_table[:login_attempts].gteq(MAX_LOGIN_ATTEMPTS)) }

  # TODO: remove `chronic` field from schema
  enum target_audience: { kid: 0, elderly: 1, chronic: 2, disabled: 3, pregnant: 4, postpartum: 5,
                          teacher: 6, over55: 7, without_target: 8 }

  def cpf=(c)
    self[:cpf] = c.gsub(/[^\d]/, '')
  end

  def conditions
    CONDITIONS.select { |_, f| f.call(self) }.map { |c, _| c }
  end

  def can_schedule?
    conditions.any?
  end

  def has_future_appointments?
    appointments
      .future
      .active
      .any?
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

  def age
    ((Time.zone.now - birth_date.to_time) / 1.year.seconds).floor
  end

  # Until we have a proper way to remember vaccines for patients
  def got_first_dose?
    appointments.active.checked_out.count.positive?
  end

  # Until we have a proper way to remember vaccines for patients
  def got_second_dose?
    appointments.active.checked_out.count >= 2
  end

  def vaccinated?
    got_second_dose?
  end

  def allowed?
    can_schedule? || has_future_appointments?
  end

  def birthday=(date)
    date = [date[1], date[2], date[3]].join('-') if date.is_a? Hash
    self[:birth_date] = Date.iso8601(date)
  end

  def birthday
    return nil if self[:birth_date].blank?

    Date.iso8601(self[:birth_date])
  end

  def mothers_first_name
    mother_name.split.first.downcase.camelize
  end

  def match_mothers_name?(try)
    mothers_first_name == try.downcase.camelize
  end

  def generate_fake_mothers_list!
    update! fake_mothers: MotherNameService.name_list(mothers_first_name)
  end

  def record_failed_login!
    update! login_attempts: login_attempts + 1
  end

  def record_successful_login!
    update! login_attempts: 0, fake_mothers: nil
  end

  def locked?
    remaining_login_attempts <= 0
  end

  def remaining_login_attempts
    MAX_LOGIN_ATTEMPTS - login_attempts
  end

  private

  def valid_birth_date
    Date.parse(birth_date)
  rescue ArgumentError
    errors.add(:birth_date, :invalid)
  end
end
