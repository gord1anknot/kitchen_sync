require File.expand_path(File.join(File.dirname(__FILE__), 'test_helper'))

class RowsFromTest < KitchenSync::EndpointTestCase
  include TestTableSchemas

  def from_or_to
    :from
  end

  test_each "returns an empty array if there are no such rows, extending the range to the end of the table if there are no later rows" do
    create_some_tables
    send_handshake_commands

    send_command   Commands::ROWS, ["footbl", [], []]
    expect_command Commands::ROWS,
                   ["footbl", [], []]

    send_command   Commands::ROWS, ["footbl", [0], [0]]
    expect_command Commands::ROWS,
                   ["footbl", [0], [0]]

    send_command   Commands::ROWS, ["footbl", [-1], [0]]
    expect_command Commands::ROWS,
                   ["footbl", [-1], [0]]

    send_command   Commands::ROWS, ["footbl", [10], [11]]
    expect_command Commands::ROWS,
                   ["footbl", [10], [11]]

    send_command   Commands::ROWS, ["secondtbl", [], []]
    expect_command Commands::ROWS,
                   ["secondtbl", [], []]
    send_command   Commands::ROWS, ["secondtbl", ["aa", 0], ["ab", 0]]
    expect_command Commands::ROWS,
                   ["secondtbl", ["aa", 0], ["ab", 0]]
  end

  test_each "returns all the rows whose key is greater than the first argument and not greater than the last argument" do
    create_some_tables
    execute "INSERT INTO footbl VALUES (2, 10, 'test'), (4, NULL, 'foo'), (5, NULL, NULL), (8, -1, 'longer str')"
    @rows = [[2,  10,       "test"],
             [4, nil,        "foo"],
             [5, nil,          nil],
             [8,  -1, "longer str"]]
    @keys = @rows.collect {|row| [row[0]]}
    send_handshake_commands

    send_command   Commands::ROWS, ["footbl", [1], [2]]
    expect_command Commands::ROWS,
                   ["footbl", [1], [2]],
                   @rows[0]

    send_command   Commands::ROWS, ["footbl", [1], [2]] # same request
    expect_command Commands::ROWS,
                   ["footbl", [1], [2]],
                   @rows[0]

    send_command   Commands::ROWS, ["footbl", [0], [2]] # different request, but same data matched
    expect_command Commands::ROWS,
                   ["footbl", [0], [2]],
                   @rows[0]

    send_command   Commands::ROWS, ["footbl", [1], [3]] # ibid
    expect_command Commands::ROWS,
                   ["footbl", [1], [3]],
                   @rows[0]

    send_command   Commands::ROWS, ["footbl", [3], [4]] # null numbers
    expect_command Commands::ROWS,
                   ["footbl", [3], [4]],
                   @rows[1]

    send_command   Commands::ROWS, ["footbl", [4], [5]] # null strings
    expect_command Commands::ROWS,
                   ["footbl", [4], [5]],
                   @rows[2]

    send_command   Commands::ROWS, ["footbl", [5], [9]] # negative numbers
    expect_command Commands::ROWS,
                   ["footbl", [5], [9]],
                   @rows[3]

    send_command   Commands::ROWS, ["footbl", [0], [10]]
    expect_command Commands::ROWS,
                   ["footbl", [0], [10]],
                   *@rows
  end

  test_each "starts from the first row if an empty array is given as the first argument" do
    create_some_tables
    execute "INSERT INTO footbl VALUES (2, 3, 'foo'), (4, 5, 'bar')"
    @rows = [[2, 3, "foo"],
             [4, 5, "bar"]]
    @keys = @rows.collect {|row| [row[0]]}
    send_handshake_commands

    send_command   Commands::ROWS, ["footbl", [], @keys[0]]
    expect_command Commands::ROWS,
                   ["footbl", [], @keys[0]],
                   @rows[0]

    send_command   Commands::ROWS, ["footbl", [], @keys[1]]
    expect_command Commands::ROWS,
                   ["footbl", [], @keys[1]],
                   @rows[0],
                   @rows[1]

    send_command   Commands::ROWS, ["footbl", [], [10]]
    expect_command Commands::ROWS,
                   ["footbl", [], [10]],
                   @rows[0],
                   @rows[1]
  end

  test_each "supports composite keys" do
    create_some_tables
    execute "INSERT INTO secondtbl VALUES (2, 2349174, 'xy', 1), (9, 968116383, 'aa', 9), (100, 100, 'aa', 100), (340, 363401169, 'ab', 20)"
    send_handshake_commands

    # note when reading these that the primary key columns are in reverse order to the table definition; the command arguments need to be given in the key order, but the column order for the results is unrelated

    send_command   Commands::ROWS, ["secondtbl", ["aa", 1], ["zz", 2147483647]]
    expect_command Commands::ROWS,
                   ["secondtbl", ["aa", 1], ["zz", 2147483647]],
                   [100,       100, "aa", 100], # first because aa is the first term in the key, then 100 the next
                   [  9, 968116383, "aa",   9],
                   [340, 363401169, "ab",  20],
                   [  2,   2349174, "xy",   1]

    send_command   Commands::ROWS, ["secondtbl", ["aa", 101], ["aa", 1000000000]]
    expect_command Commands::ROWS,
                   ["secondtbl", ["aa", 101], ["aa", 1000000000]],
                   [9, 968116383, "aa", 9]

    send_command   Commands::ROWS, ["secondtbl", ["aa", 100], ["aa", 1000000000]]
    expect_command Commands::ROWS,
                   ["secondtbl", ["aa", 100], ["aa", 1000000000]],
                   [9, 968116383, "aa", 9]

    send_command   Commands::ROWS, ["secondtbl", ["ww", 1], ["zz", 1]]
    expect_command Commands::ROWS,
                   ["secondtbl", ["ww", 1], ["zz", 1]],
                   [2, 2349174, "xy", 1]

    send_command   Commands::ROWS, ["secondtbl", ["xy", 1], ["xy", 10000000]]
    expect_command Commands::ROWS,
                   ["secondtbl", ["xy", 1], ["xy", 10000000]],
                   [2, 2349174, "xy", 1]
  end

  test_each "supports reserved-word column names" do
    clear_schema
    create_reservedtbl
    send_handshake_commands

    send_command   Commands::ROWS, ["reservedtbl", [], []]
    expect_command Commands::ROWS,
                   ["reservedtbl", [], []]

    send_command   Commands::ROWS, ["reservedtbl", [], []]
    expect_command Commands::ROWS,
                   ["reservedtbl", [], []]
  end

  test_each "uses a consistent format for misc column types such as dates and times" do
    clear_schema
    create_misctbl
    execute "INSERT INTO misctbl (pri, boolfield, datefield, timefield, datetimefield, floatfield, doublefield, decimalfield, vchrfield, fchrfield, textfield, blobfield) VALUES " \
            "                    (1, true, '2018-12-31', '23:59', '2018-12-31 23:59', 1.0, 0.5, 012345.6789, 'vchrvalue', 'fchrvalue', 'textvalue', 'blobvalue')"
    send_handshake_commands

    # note that we currently use string format for float and double fields, though we could convert them to proper msgpack types instead
    # this works OK as long as all the adapters do the same thing
    send_command   Commands::ROWS, ["misctbl", [], []]
    expect_command Commands::ROWS,
                   ["misctbl", [], []],
                   [1, true, '2018-12-31', '23:59:00', '2018-12-31 23:59:00', '1', '0.5', '12345.6789', 'vchrvalue', 'fchrvalue', 'textvalue', 'blobvalue']
  end
end
