# frozen_string_literal: true

module Qt
  module Inspectable
    def q_inspect
      property_values = {}
      self.class::QT_API_PROPERTIES.each do |property|
        begin
          property_values[property] = public_send(property)
        rescue StandardError => e
          property_values[property] = { error: e.class.name, message: e.message }
        end
      end

      {
        qt_class: self.class::QT_CLASS,
        ruby_class: self.class.name,
        handle: @handle,
        qt_methods: self.class::QT_API_QT_METHODS,
        ruby_methods: self.class::QT_API_RUBY_METHODS,
        properties: property_values
      }
    end
    alias_method :qt_inspect, :q_inspect
    alias_method :to_h, :q_inspect
  end
end
