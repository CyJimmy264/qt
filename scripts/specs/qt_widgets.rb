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
        methods: [],
        auto_methods: [
          { qt_name: 'setWindowTitle', param_count: 1 },
          { qt_name: 'resize', param_count: 2 },
          { qt_name: 'setLayout', param_count: 1 },
          { qt_name: 'setGeometry', param_count: 4 },
          { qt_name: 'setStyleSheet', param_count: 1 },
          { qt_name: 'setFocusPolicy', param_count: 1 },
          { qt_name: 'show', param_count: 0 },
          { qt_name: 'hide', param_count: 0 },
          { qt_name: 'isVisible', param_count: 0 },
          { qt_name: 'x', param_count: 0 },
          { qt_name: 'y', param_count: 0 },
          { qt_name: 'width', param_count: 0 },
          { qt_name: 'height', param_count: 0 }
        ],
        validate: { constructors: ['QWidget'], methods: ['setWindowTitle', 'resize', 'setLayout', 'setGeometry', 'setStyleSheet', 'show', 'hide', 'isVisible', 'x', 'y', 'width', 'height'] }
      },
      {
        qt_class: 'QLabel',
        ruby_class: 'QLabel',
        include: 'QLabel',
        prefix: 'qlabel',
        constructor: { parent: true, parent_type: 'QWidget*', register_in_parent: true },
        methods: [],
        auto_methods: [
          { qt_name: 'setText', param_count: 1 },
          { qt_name: 'setAlignment', param_count: 1, param_types: ['Qt::Alignment'] }
        ],
        validate: { constructors: ['QLabel'], methods: ['setText', 'setAlignment'] }
      },
      {
        qt_class: 'QPushButton',
        ruby_class: 'QPushButton',
        include: 'QPushButton',
        prefix: 'qpush_button',
        constructor: { parent: true, parent_type: 'QWidget*', register_in_parent: true },
        methods: [],
        auto_methods: [
          { qt_name: 'setText', param_count: 1 },
          { qt_name: 'click', param_count: 0 }
        ],
        validate: { constructors: ['QPushButton'], methods: [] }
      },
      {
        qt_class: 'QLineEdit',
        ruby_class: 'QLineEdit',
        include: 'QLineEdit',
        prefix: 'qline_edit',
        constructor: { parent: true, parent_type: 'QWidget*', register_in_parent: true },
        methods: [],
        auto_methods: [
          { qt_name: 'setText', param_count: 1 },
          { qt_name: 'setPlaceholderText', param_count: 1 }
        ],
        validate: { constructors: ['QLineEdit'], methods: [] }
      },
      {
        qt_class: 'QVBoxLayout',
        ruby_class: 'QVBoxLayout',
        include: 'QVBoxLayout',
        prefix: 'qvbox_layout',
        constructor: { parent: true, parent_type: 'QWidget*', register_in_parent: false },
        methods: [],
        auto_methods: [
          { qt_name: 'addWidget', param_count: 1 },
          { qt_name: 'removeWidget', param_count: 1 }
        ],
        validate: { constructors: ['QVBoxLayout'], methods: [] }
      },
      {
        qt_class: 'QTableWidget',
        ruby_class: 'QTableWidget',
        include: 'QTableWidget',
        prefix: 'qtable_widget',
        constructor: { parent: true, parent_type: 'QWidget*', register_in_parent: true },
        methods: [],
        auto_methods: [
          { qt_name: 'setColumnCount', param_count: 1 },
          { qt_name: 'setRowCount', param_count: 1 },
          { qt_name: 'setColumnWidth', param_count: 2 },
          { qt_name: 'setRowHeight', param_count: 2 },
          { qt_name: 'setVerticalScrollMode', param_count: 1, arg_casts: ['QAbstractItemView::ScrollMode'] },
          { qt_name: 'setHorizontalScrollBarPolicy', param_count: 1 },
          { qt_name: 'setHorizontalHeaderItem', param_count: 2 },
          { qt_name: 'setItem', param_count: 3 },
          { qt_name: 'item', param_count: 2 },
          { qt_name: 'setCurrentCell', param_count: 2 },
          { qt_name: 'currentRow', param_count: 0 },
          { qt_name: 'currentColumn', param_count: 0 },
          { qt_name: 'clearContents', param_count: 0 },
          { qt_name: 'setCellWidget', param_count: 3 }
        ],
        validate: { constructors: ['QTableWidget'], methods: [] }
      },
      {
        qt_class: 'QTableWidgetItem',
        ruby_class: 'QTableWidgetItem',
        include: 'QTableWidgetItem',
        prefix: 'qtable_widget_item',
        constructor: { parent: false },
        methods: [],
        auto_methods: [
          { qt_name: 'setText', param_count: 1 },
          { qt_name: 'text', param_count: 0 },
          { qt_name: 'setTextAlignment', param_count: 1, param_types: ['Qt::Alignment'] }
        ],
        validate: { constructors: ['QTableWidgetItem'], methods: [] }
      },
      {
        qt_class: 'QScrollArea',
        ruby_class: 'QScrollArea',
        include: 'QScrollArea',
        prefix: 'qscroll_area',
        constructor: { parent: true, parent_type: 'QWidget*', register_in_parent: true },
        methods: [],
        auto_methods: [
          { qt_name: 'setWidgetResizable', param_count: 1 },
          { qt_name: 'setWidget', param_count: 1 }
        ],
        validate: { constructors: ['QScrollArea'], methods: [] }
      }
    ].freeze
  end
end
