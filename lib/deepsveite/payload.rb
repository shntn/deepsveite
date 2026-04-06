# frozen_string_literal: true

module DeepSveite
  class Payload
    def self.field(name, width: 64, enum: nil)
      @_fields ||= []
      @_fields << { name: name, width: width, enum: enum }
      attr_accessor name
    end

    def self._fields
      @_fields || []
    end

    def initialize(**kwargs)
      kwargs.each { |k, v| send(:"#{k}=", v) }
    end

    # VCD記録用: enum対応の整数値を返す
    def _field_int_value(name)
      val      = send(name)
      field_def = self.class._fields.find { |f| f[:name] == name }
      return 0 unless field_def
      if field_def[:enum] && (val.is_a?(Symbol) || val.is_a?(String))
        field_def[:enum][val.to_sym] || field_def[:enum][val.to_s] || 0
      elsif val.is_a?(Integer)
        val
      else
        0
      end
    end
  end
end
