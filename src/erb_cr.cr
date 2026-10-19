require "attr_reader_cr"
require "html"
# erb_cr — ERB-синтаксис с семантикой Rails, компилируемый в методы-рендеры
# на этапе сборки (через macro `run()`, как stdlib ECR).
#
# `<%= %>` экранирует (кроме SafeString), `<% %>` — управляющий код,
# блочные хелперы (`<%= helper do %> ... <% end %>`) работают через
# общий буфер вывода.

require "./output_safety"
require "./rendering"
