require 'pg'

ENDPOINT_DATABASES["postgresql"] = {
  :connect => lambda { |host, port, name, username, password|
    PG::BasicTypeRegistry.alias_type(0, 'time', 'text')
    PG.connect(
      host,
      port,
      nil,
      nil,
      name,
      username,
      password).tap {|conn| conn.type_map_for_results = PG::BasicTypeMapForResults.new(conn)}
  }
}

class PG::Connection
  def execute(sql)
    async_exec(sql)
  end

  def tables
    query("SELECT tablename::TEXT FROM pg_tables WHERE schemaname = ANY (current_schemas(false)) ORDER BY tablename").collect {|row| row["tablename"]}
  end

  def views
    query("SELECT viewname::TEXT FROM pg_views WHERE schemaname = ANY (current_schemas(false)) ORDER BY viewname").collect {|row| row["viewname"]}
  end

  def table_primary_key_name(table_name)
    "#{table_name}_pkey"
  end

  def table_keys(table_name)
    query(<<-SQL).collect {|row| row["relname"]}
      SELECT index_class.relname::TEXT
        FROM pg_class table_class, pg_index, pg_class index_class
       WHERE table_class.relname = '#{table_name}' AND
             table_class.oid = pg_index.indrelid AND
             index_class.oid = pg_index.indexrelid AND
             index_class.relkind = 'i' AND
             NOT pg_index.indisprimary
    SQL
  end

  def table_keys_unique(table_name)
    query(<<-SQL).each_with_object({}) {|row, results| results[row["relname"]] = row["indisunique"]}
      SELECT index_class.relname::TEXT, indisunique
        FROM pg_class table_class, pg_index, pg_class index_class
       WHERE table_class.relname = '#{table_name}' AND
             table_class.oid = pg_index.indrelid AND
             index_class.oid = pg_index.indexrelid AND
             index_class.relkind = 'i' AND
             NOT pg_index.indisprimary
    SQL
  end

  def key_definition_columns(definition)
    if definition =~ /\((.*)\)$/
      $1.split(', ')
    end
  end

  def table_key_columns(table_name)
    query(<<-SQL).each_with_object({}) {|row, results| results[row["relname"]] = key_definition_columns(row["definition"])}
      SELECT index_class.relname::TEXT, pg_get_indexdef(indexrelid) AS definition
        FROM pg_class table_class, pg_class index_class, pg_index
       WHERE table_class.relname = '#{table_name}' AND
             table_class.relkind = 'r' AND
             index_class.relkind = 'i' AND
             pg_index.indrelid = table_class.oid AND
             pg_index.indexrelid = index_class.oid
       ORDER BY relname
    SQL
  end

  def table_column_names(table_name)
    query(<<-SQL).collect {|row| row["attname"]}
      SELECT attname::TEXT
        FROM pg_attribute, pg_class
       WHERE attrelid = pg_class.oid AND
             attnum > 0 AND
             NOT attisdropped AND
             relname = '#{table_name}'
       ORDER BY attnum
    SQL
  end

  def table_column_types(table_name)
    query(<<-SQL).collect.with_object({}) {|row, results| results[row["attname"]] = row["atttype"]}
      SELECT attname::TEXT, format_type(atttypid, atttypmod) AS atttype
        FROM pg_attribute, pg_class, pg_type
       WHERE attrelid = pg_class.oid AND
             atttypid = pg_type.oid AND
             attnum > 0 AND
             NOT attisdropped AND
             relname = '#{table_name}'
       ORDER BY attnum
    SQL
  end

  def table_column_nullability(table_name)
    query(<<-SQL).collect.with_object({}) {|row, results| results[row["attname"]] = !row["attnotnull"]}
      SELECT attname::TEXT, attnotnull
        FROM pg_attribute, pg_class
       WHERE attrelid = pg_class.oid AND
             attnum > 0 AND
             NOT attisdropped AND
             relname = '#{table_name}'
       ORDER BY attnum
    SQL
  end

  def table_column_defaults(table_name)
    query(<<-SQL).collect.with_object({}) {|row, results| results[row["attname"]] = row["attdefault"].try!(:gsub, /^'(.*)'::.*$/, '\\1')}
      SELECT attname::TEXT, (CASE WHEN atthasdef THEN pg_get_expr(adbin, adrelid) ELSE NULL END) AS attdefault
        FROM pg_attribute
        JOIN pg_class ON attrelid = pg_class.oid
        LEFT JOIN pg_attrdef ON adrelid = attrelid AND adnum = attnum
       WHERE attnum > 0 AND
             NOT attisdropped AND
             relname = '#{table_name}'
       ORDER BY attnum
    SQL
  end

  def table_column_sequences(table_name)
    table_column_defaults(table_name).collect.with_object({}) {|(column, default), results| results[column] = !!(default =~ /^nextval\('\w+_seq'::regclass\)/)}
  end

  def quote_ident(name)
    self.class.quote_ident(name)
  end

  def zero_time_value
    "00:00:00"
  end
end
