;; extends
((call_expression
  function: (member_expression) @_vimcmd_identifier
  arguments: (arguments ((string) @vim (#offset! @vim 0 1 0 -1))))
  (#eq? @_vimcmd_identifier "denops.cmd"))
((call_expression
  function: (member_expression) @_vimcmd_identifier
  arguments: (arguments ((template_string) @vim (#offset! @vim 0 1 0 -1))))
  (#eq? @_vimcmd_identifier "denops.cmd"))
