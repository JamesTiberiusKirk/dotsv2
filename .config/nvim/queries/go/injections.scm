;; extends

; method-name based injection for strings passed directly to SQL methods
((call_expression
  (selector_expression
    field: (field_identifier) @_field)
  (argument_list
    (interpreted_string_literal
      (interpreted_string_literal_content) @injection.content)))
  (#any-of? @_field "Exec" "GetContext" "ExecContext" "SelectContext" "In"
                     "RebindNamed" "Rebind" "Query" "QueryRow" "QueryRowxContext" "NamedExec" "MustExec" "Get" "Queryx")
  (#set! injection.language "sql"))

; method-name based injection for concatenated strings (e.g. query+" AND ...")
((call_expression
  (selector_expression
    field: (field_identifier) @_field)
  (argument_list
    (binary_expression
      (interpreted_string_literal
        (interpreted_string_literal_content) @injection.content))))
  (#any-of? @_field "Exec" "GetContext" "ExecContext" "SelectContext" "In"
                     "RebindNamed" "Rebind" "Query" "QueryRow" "QueryRowxContext" "NamedExec" "MustExec" "Get" "Queryx")
  (#set! injection.language "sql"))

; regex-based injection for standalone SQL strings
([
  (interpreted_string_literal_content)
  (raw_string_literal_content)
  ] @injection.content
 (#match? @injection.content "(SELECT|select|INSERT|insert|UPDATE|update|DELETE|delete).+(FROM|from|INTO|into|VALUES|values|SET|set).*(WHERE|where|GROUP BY|group by)?")
(#set! injection.language "sql"))

; ----------------------------------------------------------------
; fallback keyword and comment based injection
;
([
  (interpreted_string_literal_content)
  (raw_string_literal_content)
 ] @injection.content
 (#contains? @injection.content "-- sql" "--sql" "ADD CONSTRAINT" "ALTER TABLE" "ALTER COLUMN"
                  "DATABASE" "FOREIGN KEY" "GROUP BY" "HAVING" "CREATE INDEX" "INSERT INTO"
                  "NOT NULL" "PRIMARY KEY" "UPDATE SET" "TRUNCATE TABLE" "LEFT JOIN" "add constraint" "alter table" "alter column" "database" "foreign key" "group by" "having" "create index" "insert into"
                  "not null" "primary key" "update set" "truncate table" "left join")
 (#set! injection.language "sql"))


; json
(const_spec
  name: (identifier)
  value: (expression_list
	   (raw_string_literal
	     (raw_string_literal_content) @injection.content
             (#lua-match? @injection.content "^[\n|\t| ]*\{.*\}[\n|\t| ]*$")
             (#set! injection.language "json")
	    )
  )
)

(short_var_declaration
    left: (expression_list (identifier))
    right: (expression_list
             (raw_string_literal
               (raw_string_literal_content) @injection.content
               (#lua-match? @injection.content "^[\n|\t| ]*\{.*\}[\n|\t| ]*$")
               (#set! injection.language "json")
             )
    )
)

(var_spec
  name: (identifier)
  value: (expression_list
           (raw_string_literal
             (raw_string_literal_content) @injection.content
             (#lua-match? @injection.content "^[\n|\t| ]*\{.*\}[\n|\t| ]*$")
             (#set! injection.language "json")
           )
  )
)
