" dispatch.vim iTerm strategy

if exists('g:autoloaded_dispatch_iterm')
  finish
endif
let g:autoloaded_dispatch_iterm = 1

function! dispatch#iterm#handle(request) abort
  if $TERM_PROGRAM !=# 'iTerm.app' && !(has('gui_macvim') && has('gui_running'))
    return 0
  endif
  if a:request.action ==# 'make'
    if !get(a:request, 'background', 0) && !has('gui_running')
      return 0
    endif
    let exec = dispatch#prepare_make(a:request)
    return dispatch#iterm#spawn(exec, a:request, 0)
  elseif a:request.action ==# 'start'
    return dispatch#iterm#spawn(a:request.expanded, a:request, !a:request.background)
  endif
endfunction

function! dispatch#iterm#spawn(command, request, activate) abort
  let script = dispatch#isolate(dispatch#set_title(a:request), a:command)
  return s:osascript(
      \ 'tell application "iTerm"',
      \   'tell the current terminal',
      \     'set oldsession to the current session',
      \     'tell (make new session)',
      \       'set name to '.s:escape(a:request.title),
      \       'set title to '.s:escape(a:request.command),
      \       'exec command ' . s:escape(script),
      \       a:request.background ? 'select oldsession' : '',
      \     'end tell',
      \   'end tell',
      \   a:activate ? 'activate' : '',
      \ 'end tell')
endfunction

function! s:osascript(...) abort
  call system('osascript'.join(map(copy(a:000), '" -e ".shellescape(v:val)'), ''))
  return !v:shell_error
endfunction

function! s:escape(string)
  return '"'.escape(a:string, '"\').'"'
endfunction
