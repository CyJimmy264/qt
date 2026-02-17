# frozen_string_literal: true

module QtRubyGenerator
  module Specs
    CLASS_SPECS = [
      {
        qt_class: 'QApplication',
        ruby_class: 'QApplication',
        prefix: 'qapplication',
        constructor: { parent: false, mode: :qapplication },
        class_methods: [
          { ruby_name: 'qtVersion', native: 'qt_version', args: [] }
        ],
        methods: [
          { qt_name: 'exec', ruby_name: 'exec', ffi_return: :int, args: [] }
        ],
        validate: { constructors: ['QApplication'], methods: ['exec'] }
      },
      {
        qt_class: 'QWidget',
        ruby_class: 'QWidget',
        prefix: 'qwidget',
        constructor: { parent: true, parent_type: 'QWidget*' },
        methods: [
          {
            qt_name: 'setWindowTitle',
            ruby_name: 'setWindowTitle',
            ffi_return: :void,
            args: [{ name: 'title', ffi: :string, cast: :qstring }]
          },
          {
            qt_name: 'resize',
            ruby_name: 'resize',
            ffi_return: :void,
            args: [
              { name: 'width', ffi: :int },
              { name: 'height', ffi: :int }
            ]
          },
          { qt_name: 'show', ruby_name: 'show', ffi_return: :void, args: [] }
        ],
        validate: { constructors: ['QWidget'], methods: ['setWindowTitle', 'resize', 'show'] }
      },
      {
        qt_class: 'QLabel',
        ruby_class: 'QLabel',
        prefix: 'qlabel',
        constructor: { parent: true, parent_type: 'QWidget*' },
        methods: [
          {
            qt_name: 'setText',
            ruby_name: 'setText',
            ffi_return: :void,
            args: [{ name: 'text', ffi: :string, cast: :qstring }]
          },
          {
            qt_name: 'setAlignment',
            ruby_name: 'setAlignment',
            ffi_return: :void,
            args: [{ name: 'alignment', ffi: :int, cast: :alignment }]
          },
          {
            qt_name: 'setGeometry',
            ruby_name: 'setGeometry',
            ffi_return: :void,
            args: [
              { name: 'x', ffi: :int },
              { name: 'y', ffi: :int },
              { name: 'width', ffi: :int },
              { name: 'height', ffi: :int }
            ]
          }
        ],
        validate: { constructors: ['QLabel'], methods: ['setText', 'setAlignment'] }
      }
    ].freeze
  end
end
