function! s:isFunction(oneLine)
  if a:oneLine
    return getline('.') =~ '\<function\>[^(]*(.*)\s*{.*}\|(.*)\s*=>\s*{.*}'
  else
    return getline('.') =~ '\<function\>[^(]*(.*)\s*{\|(.*)\s*=>\s*{'
  endif
endfunction

function! sj#js#SplitObjectLiteral()
  let [from, to] = sj#LocateBracesOnLine('{', '}')

  if from < 0 && to < 0
    return 0
  else
    let pairs = sj#ParseJsonObjectBody(from + 1, to - 1)
    let body  = "{\n".join(pairs, ",\n")."\n}"
    if sj#settings#Read('trailing_comma') && !s:isFunction(0)
      let body = substitute(body, ',\?\n}', ',\n}', '')
    endif
    call sj#ReplaceMotion('Va{', body)

    if sj#settings#Read('align')
      let body_start = line('.') + 1
      let body_end   = body_start + len(pairs) - 1
      call sj#Align(body_start, body_end, 'json_object')
    endif

    return 1
  endif
endfunction

function! sj#js#SplitFunction()
  if expand('<cword>') == 'function' && s:isFunction(1)
    normal! f{
    return sj#js#SplitObjectLiteral()
  else
    return 0
  endif
endfunction

function! sj#js#JoinObjectLiteral()
  let line = getline('.')

  if line =~ '{\s*$'
    call search('{', 'c', line('.'))
    let body = sj#GetMotion('Vi{')

    let lines = split(body, "\n")
    let lines = sj#TrimList(lines)
    if sj#settings#Read('normalize_whitespace')
      let lines = map(lines, 'substitute(v:val, ",\\s\\{2,}", ", ", "")')
      let lines = map(lines, 'substitute(v:val, ":\\s\\+", ": ", "")')
    endif

    let body = join(lines, ' ')
    if sj#settings#Read('trailing_comma')
      let body = substitute(body, ',\?$', '', '')
    endif

    let body = '{'.body.'}'

    call sj#ReplaceMotion('Va{', body)

    return 1
  else
    return 0
  endif
endfunction

function! sj#js#JoinFunction()
  let line = getline('.')

  if line =~ 'function\%(\s\+\k\+\)\=(.*) {\s*$'
    call search('{', 'c', line('.'))
    let body = sj#GetMotion('Vi{')

    let lines = split(body, ';\=\s*\n')
    let lines = sj#TrimList(lines)
    let body = join(lines, '; ').';'
    let body = '{ '.body.' }'

    call sj#ReplaceMotion('Va{', body)

    return 1
  else
    return 0
  endif
endfunction

function! s:SplitList(regex, opening_char, closing_char, no_trail)
  if sj#SearchUnderCursor(a:regex) <= 0
    return 0
  endif

  call sj#PushCursor()

  let lineno = line('.')
  let indent = indent('.')

  " TODO (2012-10-24) connect sj#SearchUnderCursor and sj#LocateBracesOnLine
  normal! l
  let start = col('.')
  normal! h%h
  let end = col('.')

  let items = sj#ParseJsonObjectBody(start, end)

  if sj#settings#Read('trailing_comma') && !a:no_trail
    let body = a:opening_char."\n".join(items, ",\n").",\n".a:closing_char
  else
    let body = a:opening_char."\n".join(items, ",\n")."\n".a:closing_char
  endif

  call sj#PopCursor()

  call sj#ReplaceMotion('va'.a:opening_char, body)

  " built-in js indenting doesn't indent this properly
  for l in range(lineno + 1, lineno + len(items))
    call sj#SetIndent(l, indent + &sw)
  endfor
  " closing bracket
  let end_line = lineno + len(items) + 1
  call sj#SetIndent(end_line, indent)

  return 1
endfunction

function! sj#js#SplitArray()
  return s:SplitList('\[[^]]*]', '[', ']', 0)
endfunction

function! sj#js#SplitArgs()
  " Don't split a function declaration's args
  if s:isFunction(0)
    return 0
  endif

  return s:SplitList('([^)]*)', '(', ')', 1)
endfunction

function! s:JoinList(regex, opening_char, closing_char)
  if sj#SearchUnderCursor(a:regex) <= 0
    return 0
  endif

  let body = sj#GetMotion('va'.a:opening_char)
  let body = substitute(body, '\_s\+', ' ', 'g')
  let body = substitute(body, '^'.a:opening_char.'\s\+', a:opening_char, '')
  if sj#settings#Read('trailing_comma')
    let body = substitute(body, ',\?\s\+'.a:closing_char.'$', a:closing_char, '')
  else
    let body = substitute(body, '\s\+'.a:closing_char.'$', a:closing_char, '')
  endif

  call sj#ReplaceMotion('va'.a:opening_char, body)

  return 1
endfunction

function! sj#js#JoinArray()
  return s:JoinList('\[[^]]*\s*$', '[', ']')
endfunction

function! sj#js#JoinArgs()
  return s:JoinList('([^)]*\s*$', '(', ')')
endfunction

function! sj#js#SplitOneLineIf()
  let line = getline('.')
  if line =~ '^\s*if (.\+) .\+;'
    let lines = []
    " use regular vim movements to know where we have to split
    normal! ^w%
    let end_if = getpos('.')[2]
    call add(lines, line[0:end_if] . '{')
    call add(lines, sj#Trim(line[end_if :]))
    call add(lines, '}')

    call sj#ReplaceMotion('V', join(lines, "\n"))

    return 1
  else
    return 0
  endif
endfunction

function! sj#js#JoinOneLineIf()
  let if_line_no = line('.')
  let if_line = getline('.')
  let end_line_no = if_line_no + 2
  let end_line = getline(end_line_no)

  if if_line !~ '^\s*if (.+) {' && end_line !~ '^\s*}\s*$'
    return 0
  endif

  let body = sj#Trim(getline(if_line_no + 1))
  let new  = if_line[:-2] . body

  call sj#ReplaceLines(if_line_no, end_line_no, new)
  return 1
endfunction
