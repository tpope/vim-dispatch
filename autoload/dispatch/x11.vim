" dispatch.vim X11 strategy

if exists('g:autoloaded_dispatch_x11')
  finish
endif
let g:autoloaded_dispatch_x11 = 1

function! dispatch#x11#handle(request) abort
  if $DISPLAY !~# '^:' || a:request.action !=# 'start'
    return 0
  endif
  if a:request.background && (!v:windowid || !executable('wmctrl'))
    return 0
  endif
  if !empty($TERMINAL)
    let terminal = $TERMINAL
  elseif executable('x-terminal-emulator')
    let terminal = 'x-terminal-emulator'
  elseif executable('xterm')
    let terminal = 'xterm'
  else
    return 0
  endif
  let command = dispatch#set_title(a:request) . '; ' . dispatch#prepare_start(a:request)
  call system(dispatch#shellescape(terminal, '-e', &shell, &shellcmdflag, command). ' &')
  if a:request.background
    sleep 100m
    call system('wmctrl -i -a '.v:windowid)
  endif
  return 1
endfunction

function! dispatch#x11#activate(pid) abort
  let out = system('ps ewww -p '.a:pid)
  let window = matchstr(out, 'WINDOWID=\zs\d\+')
  if !empty(window) && executable('wmctrl')
    call system('wmctrl -i -a '.window)
    return !v:shell_error
  endif
endfunction
