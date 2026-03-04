# frozen_string_literal: true

module Qt
  # Backward-compatible QShortcut#set_keys handling for QKeySequence inputs.
  module ShortcutCompat
    module_function

    def key_sequence_like?(value)
      value.is_a?(String) || value.respond_to?(:to_string) || value.respond_to?(:toString)
    end
  end
end

if defined?(Qt::QShortcut)
  module Qt
    class QShortcut
      if instance_methods(false).include?(:set_keys) && !instance_methods(false).include?(:set_keys_without_qkeysequence_compat)
        alias_method :set_keys_without_qkeysequence_compat, :set_keys
      end

      def set_keys(value)
        if respond_to?(:set_key) && ShortcutCompat.key_sequence_like?(value)
          set_key(value)
        else
          set_keys_without_qkeysequence_compat(value)
        end
      end
    end
  end
end
