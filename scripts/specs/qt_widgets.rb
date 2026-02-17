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
          { ruby_name: 'topLevelWidgetsCount', native: 'qapplication_top_level_widgets_count', args: [] }
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
          {
            qt_name: 'setStyleSheet',
            ruby_name: 'setStyleSheet',
            ffi_return: :void,
            args: [{ name: 'style', ffi: :string, cast: :qstring }]
          },
          { qt_name: 'show', ruby_name: 'show', ffi_return: :void, args: [] },
          { qt_name: 'hide', ruby_name: 'hide', ffi_return: :void, args: [] },
          { qt_name: 'isVisible', ruby_name: 'isVisible', ffi_return: :int, args: [] },
          { qt_name: 'x', ruby_name: 'x', ffi_return: :int, args: [] },
          { qt_name: 'y', ruby_name: 'y', ffi_return: :int, args: [] },
          { qt_name: 'width', ruby_name: 'width', ffi_return: :int, args: [] },
          { qt_name: 'height', ruby_name: 'height', ffi_return: :int, args: [] }
        ],
        validate: { constructors: ['QWidget'], methods: ['setWindowTitle', 'resize', 'setLayout', 'setGeometry', 'setStyleSheet', 'show', 'hide', 'isVisible', 'x', 'y', 'width', 'height'] }
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
          }
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
          }
        ],
        validate: { constructors: ['QPushButton'], methods: [] }
      },
      {
        qt_class: 'QLineEdit',
        ruby_class: 'QLineEdit',
        include: 'QLineEdit',
        prefix: 'qline_edit',
        constructor: { parent: true, parent_type: 'QWidget*', register_in_parent: true },
        methods: [
          {
            qt_name: 'setText',
            ruby_name: 'setText',
            ffi_return: :void,
            args: [{ name: 'text', ffi: :string, cast: :qstring }]
          },
          {
            qt_name: 'setPlaceholderText',
            ruby_name: 'setPlaceholderText',
            ffi_return: :void,
            args: [{ name: 'text', ffi: :string, cast: :qstring }]
          }
        ],
        validate: { constructors: ['QLineEdit'], methods: [] }
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
      },
      {
        qt_class: 'QTableWidget',
        ruby_class: 'QTableWidget',
        include: 'QTableWidget',
        prefix: 'qtable_widget',
        constructor: { parent: true, parent_type: 'QWidget*', register_in_parent: true },
        methods: [
          { qt_name: 'setColumnCount', ruby_name: 'setColumnCount', ffi_return: :void, args: [{ name: 'count', ffi: :int }] },
          { qt_name: 'setRowCount', ruby_name: 'setRowCount', ffi_return: :void, args: [{ name: 'count', ffi: :int }] },
          { qt_name: 'setColumnWidth', ruby_name: 'setColumnWidth', ffi_return: :void, args: [{ name: 'column', ffi: :int }, { name: 'width', ffi: :int }] },
          { qt_name: 'setRowHeight', ruby_name: 'setRowHeight', ffi_return: :void, args: [{ name: 'row', ffi: :int }, { name: 'height', ffi: :int }] },
          { qt_name: 'setVerticalScrollMode', ruby_name: 'setVerticalScrollMode', ffi_return: :void, args: [{ name: 'mode', ffi: :int, cast: 'QAbstractItemView::ScrollMode' }] },
          { qt_name: 'setHorizontalScrollBarPolicy', ruby_name: 'setHorizontalScrollBarPolicy', ffi_return: :void, args: [{ name: 'policy', ffi: :int, cast: 'Qt::ScrollBarPolicy' }] },
          { qt_name: 'clearContents', ruby_name: 'clearContents', ffi_return: :void, args: [] },
          {
            qt_name: 'setCellWidget',
            ruby_name: 'setCellWidget',
            ffi_return: :void,
            args: [
              { name: 'row', ffi: :int },
              { name: 'column', ffi: :int },
              { name: 'widget', ffi: :pointer, cast: 'QWidget*' }
            ]
          }
        ],
        validate: { constructors: ['QTableWidget'], methods: [] }
      },
      {
        qt_class: 'QScrollArea',
        ruby_class: 'QScrollArea',
        include: 'QScrollArea',
        prefix: 'qscroll_area',
        constructor: { parent: true, parent_type: 'QWidget*', register_in_parent: true },
        methods: [
          {
            qt_name: 'setWidgetResizable',
            ruby_name: 'setWidgetResizable',
            ffi_return: :void,
            args: [{ name: 'resizable', ffi: :int, cast: 'bool' }]
          },
          {
            qt_name: 'setWidget',
            ruby_name: 'setWidget',
            ffi_return: :void,
            args: [{ name: 'widget', ffi: :pointer, cast: 'QWidget*' }]
          }
        ],
        validate: { constructors: ['QScrollArea'], methods: [] }
      }
    ].freeze
  end
end
