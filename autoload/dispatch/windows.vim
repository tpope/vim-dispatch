" dispatch.vim Windows strategy

if exists('g:autoloaded_dispatch_windows')
  finish
endif
let g:autoloaded_dispatch_windows = 1

function! s:escape(str)
  if &shellxquote ==# '"'
    return '"' . substitute(a:str, '"', '""', 'g') . '"'
  else
    let esc = exists('+shellxescape') ? &shellxescape : '"&|<>()@^'
    return &shellquote .
          \ substitute(a:str, '['.esc.']', '^&', 'g') .
          \ get({'(': ')', '"(': ')"'}, &shellquote, &shellquote)
  endif
endfunction

function! dispatch#windows#handle(request) abort
  if !has('win32') || empty(v:servername)
    return 0
  endif
  if a:request.action ==# 'make'
    return dispatch#windows#make(a:request)
  elseif a:request.action ==# 'start'
    let title = get(a:request, 'title', matchstr(a:request.command, '\S\+'))
    return dispatch#windows#spawn(title, a:request.command, a:request.background)
  endif
endfunction

function! dispatch#windows#spawn(title, exec, background) abort
  let extra = a:background ? ' /min' : ''
  silent execute '!start /min cmd.exe /cstart ' .
        \ '"' . substitute(a:title, '"', '', 'g') . '"' . extra . ' ' .
        \ &shell . ' ' . &shellcmdflag . ' ' . s:escape(a:exec)
  return 1
endfunction

function! dispatch#windows#make(request) abort
  if &shellxquote ==# '"'
    let exec = dispatch#prepare_make(a:request)
  else
    let exec = escape(a:request.expanded, '%#!') .
          \ ' ' . dispatch#shellpipe(a:request.file) .
          \ ' & cd . > ' . a:request.file . '.complete' .
          \ ' & ' . dispatch#callback(a:request)
  endif

  return dispatch#windows#spawn(a:request.title, exec, 1)
endfunction
