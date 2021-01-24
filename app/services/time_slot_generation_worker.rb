class TimeSlotGenerationWorker
  class Options < OpenStruct
    Defaults = {
      sleep_interval: 60.seconds,
      execution_hour: 22,
      second_dose_interval: 28.days,
      # Max time ahead users will be able to see free time slots
      max_appointment_time_ahead: 3.days
    }

    def initialize(options = {})
      symbolized_options = options.symbolize_keys

      raise "Time slot generation worker options must be a hash" \
        unless options.is_a?(Hash)

      unrecognized_options = symbolized_options.keys - Defaults.keys

      raise "Unrecognized options: #{unrecognized_options.inspect}" \
        if unrecognized_options.any?

      normalized_options = Defaults.map do |key, value|
        [key, symbolized_options[key] || value]
      end.to_h

      super(normalized_options)
    end
  end

  def initialize(time_slot_generation_service:, slack_webhook_url: nil)
    @time_slot_generation_service = time_slot_generation_service
    @slack_webhook_url = slack_webhook_url
  end

  def execute(options: TimeSlotGenerationWorker::Options.new)
    loop do
      sleep(options.sleep_interval.to_i)

      current_time = Time.now.in_time_zone

      next unless current_time.hour == options.execution_hour

      # If we ever scale to multiple nodes, this ensures only one job will run
      result = ActiveRecord::Base.connection.execute(
        "INSERT INTO time_slot_generator_executions (date, status)" \
          "VALUES ('#{current_time.to_date.to_s(:db)}', 'running') " \
          "ON CONFLICT DO NOTHING RETURNING true AS inserted"
      )

      # Record already exists 
      # (SQL 'RETURNING' does not return anything on conflict)
      if result.none?
        Rails.logger.debug('Job locked by other process')
        # Sleep longer to avoid hitting the db every sleep interval, 
        # as current_time.hour == execution_hour will be true consecutively
        sleep(30.minutes.to_i)
      end

      send_slack_message("ℹ️ Iniciando geração de time slots")

      begin
        Ubs.active.each do |ubs|
          first_date = current_time + options.max_appointment_time_ahead + 1.day
          second_dose_date = first_date + options.second_dose_interval + 1.day

          [first_date, second_dose_date].each do |date|
            generation_options = TimeSlotGenerationService::Options.new(
              start_date: date.to_datetime,
              end_date: date.to_datetime,
              ubs_id: ubs.id,
              time_windows: build_ubs_time_windows(ubs),
              appointment_duration: ubs.slot_interval_minutes.minutes,
              num_spots: ubs.appointments_per_time_slot,
              # These don't exist or are incomplete on 
              # UBS record, so they must be changed here
              weekdays: [*0..6],
              excluded_dates: []
            )

            @time_slot_generation_service.execute(generation_options)
          end
        end

        TimeSlotGeneratorExecution
          .where(date: current_time.to_date)
          .update_all(status: 'done')
          
        send_slack_message("✅ Geração de time slots finalizada com sucesso")
      end
    rescue => exception
      error = "#{exception.class.name}: #{exception.message}"

      TimeSlotGeneratorExecution
        .where(date: current_time.to_date)
        .update_all(status: 'failed', details: error)

      send_slack_message(
        "‼️ ERRO: Geração de time slots falhou (#{error}). Mais detalhes no Sentry."
      )

      # TODO: enable after sentry-raven -> sentry-ruby migration
      # Sentry.capture_exception(exception)
    end
  end

  def send_slack_message(text)
    return if @slack_webhook_url.blank?

    uri = URI(@slack_webhook_url)
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request.body = { text: text }.to_json

    https.request(request)
  end
end
