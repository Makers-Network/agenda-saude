module TimeSlot
  def available_time_slots(day_range, time_now)
    slots_for_day = day_range.each_with_object({}) do |day, slots|
      slots[day] = available_time_slots_for_day(day, time_now)
    end

    slots_for_day.reject do |_day, slots|
      slots.empty?
    end
  end

  private

  def available_time_slots_for_day(day, time_now)
    appointments = Appointment.where(ubs: self).active_from_day(day)

    all_time_slots = time_slots(morning_shift(day)) + time_slots(afternoon_shift(day))

    if day.today?
      all_time_slots.reject! do |slot|
        slot[:slot_start].to_i < time_now.to_i
      end
    end

    all_time_slots - time_slots_conflicts(all_time_slots, appointments)
  end

  def time_slots_conflicts(time_slots, appointments)
    conflicts = time_slots.product(appointments).select do |time_slot, appointment|
      conflicting?(time_slot, appointment)
    end

    conflicts.map { |time_slot, _appointment| time_slot }
  end

  def conflicting?(time_slot, appointment)
    start_slot = time_slot[:slot_start]
    end_slot = time_slot[:slot_end]

    start_slot.between?(appointment.start, appointment.end-1) ||
      end_slot.between?(appointment.start+1, appointment.end)
      # TODO fix when appointment begins and ends between start_slot and end_slot
  end

  def time_slots(time_range)
    interval_seconds = slot_interval.seconds

    time_range.step(interval_seconds).each_with_object([]) do |start_timestamp, slots|
      slot_start = Time.zone.at(start_timestamp)

      slots << {
        slot_start: slot_start,
        slot_end: slot_start + slot_interval
      }
    end
  end

  def time_of_day(time, date)
    Tod::TimeOfDay.parse(time).on(date).in_time_zone
  end
end
