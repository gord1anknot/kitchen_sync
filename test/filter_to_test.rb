require File.expand_path(File.join(File.dirname(__FILE__), 'test_helper'))

require 'tempfile'

class FilterToTest < KitchenSync::EndpointTestCase
  include TestTableSchemas

  def from_or_to
    :to
  end

  def with_filter_file(contents)
    file = Tempfile.new('filter')
    file.write(contents)
    file.close
    begin
      program_env['ENDPOINT_FILTERS_FILE'] = file.path
      yield
    ensure
      file.unlink
    end
  end

  test_each "sends a 'false' where_condition for tables with a clear attribute" do
    create_some_tables
    execute "INSERT INTO footbl VALUES (2, 10, 'test'), (4, NULL, 'foo'), (5, NULL, NULL), (8, -1, 'longer str')"
    with_filter_file("footbl: clear \n") do # nonsignificant whitespace at the end should be ignored
      expect_handshake_commands

      expect_command Commands::SCHEMA
      send_command   Commands::SCHEMA, ["tables" => [footbl_def]]

      expect_command Commands::FILTERS,
                     [{"footbl" => {"where_conditions" => "false"}}]
      send_command   Commands::FILTERS
    end
  end

  test_each "sends the given SQL expressions in where_condition for tables with an only attribute" do
    create_some_tables
    execute "INSERT INTO footbl VALUES (2, 10, 'test'), (4, NULL, 'foo'), (5, NULL, NULL), (8, -1, 'longer str')"
    @filtered_rows = [[4, nil, "foo"],
                      [5, nil,   nil]]

    with_filter_file("footbl:\n  only: col1 BETWEEN 4 AND 7") do
      expect_handshake_commands

      expect_command Commands::SCHEMA
      send_command   Commands::SCHEMA, ["tables" => [footbl_def]]

      expect_command Commands::FILTERS,
                     [{"footbl" => {"where_conditions" => "col1 BETWEEN 4 AND 7"}}]
      send_command   Commands::FILTERS
    end
  end

  test_each "sends the given SQL expressions in filter_expressions for tables with a replace attribute" do
    create_some_tables
    execute "INSERT INTO footbl VALUES (2, 10, 'test'), (4, NULL, 'foo'), (5, NULL, NULL), (8, -1, 'longer str')"
    @filtered_rows = [[2,   6,       "testx"],
                      [4,   7,        "foox"],
                      [5, nil,     "default"],
                      [8,  18, "longer strx"]]

    with_filter_file("footbl:\n  replace:\n    another_col: col1 + CHAR_LENGTH(col3)\n    col3: COALESCE(col3 || 'x', 'default')") do
      expect_handshake_commands

      expect_command Commands::SCHEMA
      send_command   Commands::SCHEMA, ["tables" => [footbl_def]]

      expect_command Commands::FILTERS,
                     [{"footbl" => {"filter_expressions" => {"another_col" => "col1 + CHAR_LENGTH(col3)", "col3" => "COALESCE(col3 || 'x', 'default')"}}}]
      send_command   Commands::FILTERS
    end
  end

  test_each "sends both column filters and row filters if given" do
    create_some_tables
    execute "INSERT INTO footbl VALUES (2, 10, 'test'), (4, NULL, 'foo'), (5, NULL, NULL), (8, -1, 'longer str')"
    @filtered_rows = [[4,   7,     "foo"],
                      [5, nil, "default"]]

    with_filter_file("footbl:\n  replace:\n    another_col: col1 + CHAR_LENGTH(col3)\n    col3: COALESCE(col3, 'default')\n  only: col1 BETWEEN 4 AND 7") do
      expect_handshake_commands

      expect_command Commands::SCHEMA
      send_command   Commands::SCHEMA, ["tables" => [footbl_def]]

      expect_command Commands::FILTERS,
                     [{"footbl" => {"where_conditions" => "col1 BETWEEN 4 AND 7", "filter_expressions" => {"another_col" => "col1 + CHAR_LENGTH(col3)", "col3" => "COALESCE(col3, 'default')"}}}]
      send_command   Commands::FILTERS
    end
  end
end
