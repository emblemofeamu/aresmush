module AresMUSH
  module Pf2e

    def self.get_condition_value(char, condition)
      # Returns 0 if that condition does not have a value, nil if that condition is not present.
      c = char.pf2_conditions[condition]
      return nil if !c

      v = c['value']
      return 0 if !v

      return v
    end

    def self.set_condition(char, condition, value=nil, duration=false)
      list = char.pf2_conditions

      condition = condition.capitalize

      # Setting the value
      if value.zero?
        remove_condition(char, condition)
        return
      end

      cv = list[condition] || {}

      cv['value'] = value if value
      cv['duration'] = duration if duration
      # Placeholder so that if it doesn't have a value, it just exists on its own.
      cv['status'] = true

      list[condition] = cv

      char.update(pf2_conditions: list)
    end

    def self.remove_condition(char, condition)
      list = char.pf2_conditions

      list.delete condition

      char.update(pf2_conditions: list)
    end

  end
end
