# frozen_string_literal: true

module QtRubyGenerator
  module Specs
    CLASS_SPECS = [
      {
        qt_class: 'QApplication',
        ruby_class: 'QApplication',
        include: 'QApplication',
        prefix: 'qapplication',
        constructor: { parent: false, mode: :qapplication },
        class_methods: [
          { ruby_name: 'qtVersion', native: 'qt_version', args: [] },
          { ruby_name: 'processEvents', native: 'qapplication_process_events', args: [] },
          { ruby_name: 'topLevelWidgetsCount', native: 'qapplication_top_level_widgets_count', args: [] },
          { ruby_name: 'mouseX', native: 'qapplication_mouse_x', args: [] },
          { ruby_name: 'mouseY', native: 'qapplication_mouse_y', args: [] },
          { ruby_name: 'mouseButtons', native: 'qapplication_mouse_buttons', args: [] },
          { ruby_name: 'keyDown', native: 'qapplication_key_down', args: ['key'] }
        ],
        methods: [
          { qt_name: 'exec', ruby_name: 'exec', ffi_return: :int, args: [] }
        ],
        validate: { constructors: ['QApplication'], methods: ['exec'] }
      },
      {
        qt_class: 'QWidget',
        ruby_class: 'QWidget',
        include: 'QWidget',
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
          {
            qt_name: 'setLayout',
            ruby_name: 'setLayout',
            ffi_return: :void,
            args: [{ name: 'layout', ffi: :pointer, cast: 'QLayout*' }]
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
          },
          { qt_name: 'show', ruby_name: 'show', ffi_return: :void, args: [] },
          { qt_name: 'hide', ruby_name: 'hide', ffi_return: :void, args: [] },
          { qt_name: 'isVisible', ruby_name: 'isVisible', ffi_return: :int, args: [] },
          { qt_name: 'x', ruby_name: 'x', ffi_return: :int, args: [] },
          { qt_name: 'y', ruby_name: 'y', ffi_return: :int, args: [] }
        ],
        validate: { constructors: ['QWidget'], methods: ['setWindowTitle', 'resize', 'setLayout', 'setGeometry', 'show', 'hide', 'isVisible', 'x', 'y'] }
      },
      {
        qt_class: 'QLabel',
        ruby_class: 'QLabel',
        include: 'QLabel',
        prefix: 'qlabel',
        constructor: { parent: true, parent_type: 'QWidget*', register_in_parent: true },
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
          },
          {
            qt_name: 'setStyleSheet',
            ruby_name: 'setStyleSheet',
            ffi_return: :void,
            args: [{ name: 'style', ffi: :string, cast: :qstring }]
          },
          { qt_name: 'hide', ruby_name: 'hide', ffi_return: :void, args: [] }
        ],
        validate: { constructors: ['QLabel'], methods: ['setText', 'setAlignment'] }
      },
      {
        qt_class: 'QPushButton',
        ruby_class: 'QPushButton',
        include: 'QPushButton',
        prefix: 'qpush_button',
        constructor: { parent: true, parent_type: 'QWidget*', register_in_parent: true },
        methods: [
          {
            qt_name: 'setText',
            ruby_name: 'setText',
            ffi_return: :void,
            args: [{ name: 'text', ffi: :string, cast: :qstring }]
          },
          { qt_name: 'hide', ruby_name: 'hide', ffi_return: :void, args: [] }
        ],
        validate: { constructors: ['QPushButton'], methods: [] }
      },
      {
        qt_class: 'QVBoxLayout',
        ruby_class: 'QVBoxLayout',
        include: 'QVBoxLayout',
        prefix: 'qvbox_layout',
        constructor: { parent: true, parent_type: 'QWidget*', register_in_parent: false },
        methods: [
          {
            qt_name: 'addWidget',
            ruby_name: 'addWidget',
            ffi_return: :void,
            args: [{ name: 'widget', ffi: :pointer, cast: 'QWidget*' }]
          },
          {
            qt_name: 'removeWidget',
            ruby_name: 'removeWidget',
            ffi_return: :void,
            args: [{ name: 'widget', ffi: :pointer, cast: 'QWidget*' }]
          }
        ],
        validate: { constructors: ['QVBoxLayout'], methods: [] }
      }
    ].freeze
  end
end
