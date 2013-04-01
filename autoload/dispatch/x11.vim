" dispatch.vim X11 strategy

if exists('g:autoloaded_dispatch_x11')
  finish
endif
let g:autoloaded_dispatch_x11 = 1

function! dispatch#x11#handle(request) abort
  if $DISPLAY !~# '^:' || a:request.action !=# 'start' || a:request.background
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
  let command = dispatch#shellescape('printf',
        \ '\033]1;%s\007\033]2;%s\007',
        \ a:request.title,
        \ a:request.expanded) . '; '
        \ . a:request.expanded
  call system(dispatch#shellescape(terminal, '-e', &shell, &shellcmdflag, command). ' &')
  return 1
endfunction
