; inherits: go

; Inject JavaScript into script blocks
((script_block_text) @injection.content
  (#set! injection.language "javascript"))

((script_element_text) @injection.content
  (#set! injection.language "javascript"))

; Inject CSS into style elements
((style_element_text) @injection.content
  (#set! injection.language "css"))

; Inject CSS into style blocks
((style_block_text) @injection.content
  (#set! injection.language "css"))

; Keep comment injection
((element_comment) @injection.content
  (#set! injection.language "comment"))
