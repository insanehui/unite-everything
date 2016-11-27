"=============================================================================
" 
"=============================================================================

"{{{ Variables
" 这应该是unite库提供的工具api，来设置一些全局变量的缺省值

call unite#util#set_default('g:unite_source_everything_limit', 100)
" search entire path
call unite#util#set_default('g:unite_source_everything_full_path_search', 0)
" use POSIX regexp
call unite#util#set_default('g:unite_source_everything_posix_regexp_search', 0)
" sort result by full path string
call unite#util#set_default('g:unite_source_everything_sort_by_full_path', 0)
" case sensitive search
call unite#util#set_default('g:unite_source_everything_case_sensitive_search', 0)
" es.exe cmd path
call unite#util#set_default('g:unite_source_everything_cmd_path', 'es.exe')
" file ignore pattern
call unite#util#set_default('g:unite_source_everything_ignore_pattern',
      \'\%(^\|/\)\.\.\?$\|\~$\|\.\%(git\|hg\|svn\)\|\.\%(o\|exe\|dll\|bak\|DS_Store\|pyc\|zwc\|sw[po]\)$')
" minimum pattern length for asynchronous
call unite#util#set_default('g:unite_source_everything_async_minimum_length', 3)
"}}}

" es是否已安装
let s:available_es = executable(g:unite_source_everything_cmd_path)

" 构建source对象
let s:source =
      \ { 'name'                    : 'everything'
      \ , 'description'             : 'candidates from everything'
      \ , 'is_volatile'             : 1
      \ , 'max_candidates'          : 30
      \ , 'required_pattern_length' : 3
      \ , 'ignore_pattern'          : g:unite_source_everything_ignore_pattern
      \ , 'hooks' : {}
      \ }

" async的source对象
let s:source_async =
      \ { 'name'                    : 'everything/async'
      \ , 'description'             : 'asynchronous candidates from everything'
      \ , 'max_candidates'          : 1000
      \ , 'required_pattern_length' : g:unite_source_everything_async_minimum_length
      \ , 'ignore_pattern'          : g:unite_source_everything_ignore_pattern
      \ , 'hooks' : {}
      \ }

" 猜测这应该是定义source的入口函数
function! unite#sources#everything#define() "{{{
  let _ = []

  " 只支持windows
  if unite#util#is_windows() && s:available_es
    call add(_, s:source)
    if unite#util#has_vimproc()
      call add(_, s:source_async)
    endif
  endif

  return _
endfunction "}}}

function! s:source.change_candidates(args, context) "{{{
  let input = substitute(a:context.input, '^\a\+:\zs\*/', '/', '')
  " exec es.exe to list candidates
  let res = unite#util#substitute_path_separator(
        \ unite#util#system(s:es_command_line(input)))
  let candidates = split(res, '\r\n\|\r\|\n')

  return s:build_candidates(candidates)
endfunction "}}}

function! s:source.hooks.on_init(args, context)
  call s:on_init(s:source.name)
endfunction

function! s:source_async.hooks.on_init(args, context)
  call s:on_init(s:source_async.name)
endfunction

function! s:source_async.hooks.on_close(args, context) "{{{
  while !a:context.source__subproc.stdout.eof
    call a:context.source__subproc.stdout.read()
  endwhile
  call a:context.source__subproc.kill(9)
endfunction "}}}

function! s:source_async.async_gather_candidates(args, context) "{{{
  let input = substitute(a:context.input, '^\a\+:\zs\*/', '/', '')

  if !has_key(a:context, 'source__last_input') || a:context.source__last_input != input
    let a:context.source__last_input = input
    return []
  endif

  if !has_key(a:context, 'source__term') ||
        \ has_key(a:context, 'source__term') && a:context.source__term != a:context.input
    let a:context.source__term = input

    if has_key(a:context, 'source__subproc')
      call vimproc#kill(a:context.source__subproc.pid, 9)
      call remove(a:context, 'source__subproc')
      call unite#force_redraw()
    endif

    let a:context.source__subproc = vimproc#popen3(s:es_command_line(input))
  endif

  let res = []
  if has_key(a:context, 'source__subproc')
    if !a:context.source__subproc.stdout.eof
      let res = a:context.source__subproc.stdout.read_lines()
    endif
    call map(res, 'iconv(v:val, &termencoding, &encoding)')
  endif
  let candidates = map(res, 'unite#util#substitute_path_separator(v:val)')

  return s:build_candidates(candidates)
endfunction "}}}

function! s:es_command_line(input)
  return g:unite_source_everything_cmd_path
        \ . ' -n ' . g:unite_source_everything_limit
        \ . (g:unite_source_everything_case_sensitive_search > 0 ? ' -i' : '')
        \ . (g:unite_source_everything_full_path_search > 0 ? ' -p' : '')
        \ . (g:unite_source_everything_posix_regexp_search > 0 ? ' -r' : '')
        \ . (g:unite_source_everything_sort_by_full_path > 0 ? ' -s' : '')
        \ . ' ' . iconv(a:input, &encoding, &termencoding)
endfunction

function! s:build_candidates(candidate_list) "{{{
  let dir_list = []
  let file_list = []
  for candidate in a:candidate_list
    let entry = {
          \ 'word'              : candidate,
          \ 'abbr'              : candidate,
          \ 'source'            : 'everything',
          \ 'action__path'      : candidate,
          \ 'action__directory' : unite#util#path2directory(candidate),
          \	}
    if isdirectory(candidate)
      if candidate !~ '^\%(/\|\a\+:/\)$'
        let entry.abbr .= '/'
      endif
      let entry.kind = 'directory'
      call add(dir_list, entry)
    else
      let entry.kind = 'file'
      call add(file_list, entry)
    endif
  endfor

  return file_list + dir_list
endfunction "}}}

function! s:check_everything_connection()
  let cmd = g:unite_source_everything_cmd_path . ' -n 0'
  if unite#util#has_vimproc()
    call unite#util#system(cmd)
    let result = unite#util#get_last_status()
  else
    silent call system(cmd)
    let result = v:shell_error
  endif
  return result
endfunction

function! s:on_init(name)
  if s:check_everything_connection()
    call unite#print_source_error('Unable to connect to everything', a:name)
  endif
endfunction

" vim: foldmethod=marker
