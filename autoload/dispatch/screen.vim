" dispatch.vim GNU Screen strategy

if exists('g:autoloaded_dispatch_screen')
  finish
endif
let g:autoloaded_dispatch_screen = 1

let s:waiting = {}

function! dispatch#screen#handle(request) abort
  if empty($STY) || !executable('screen')
    return 0
  endif
  let aftercmd = 'screen -X only; screen -X at $WINDOW kill'
  if a:request.action ==# 'make'
    if !get(a:request, 'background', 0) && empty(v:servername) && !empty(s:waiting)
      return 0
    endif
    let cmd = dispatch#prepare_make(a:request, aftercmd)
    return dispatch#screen#spawn(cmd, a:request)
  elseif a:request.action ==# 'start'
    let cmd = dispatch#prepare_start(a:request, aftercmd)
    return dispatch#screen#spawn(cmd, a:request)
  endif
endfunction

function! dispatch#screen#spawn(command, request) abort
  let command = ''
  if !get(a:request, 'background', 0)
    silent execute "!screen -X eval 'split' 'focus down' 'resize 10'"
  endif
  let command .= 'screen -ln -fn -t '.dispatch#shellescape(a:request.title)
        \ . ' ' . &shell . ' ' . &shellcmdflag . ' '
        \ . shellescape('exec ' . dispatch#isolate(['STY', 'WINDOW'],
        \ dispatch#set_title(a:request), a:command))
  silent execute '!' . escape(command, '!#%')

  if a:request.background
    silent !screen -X other
  else
    silent !screen -X focus up
  endif

  let s:waiting = a:request
  return 1
endfunction

function! dispatch#screen#activate(pid) abort
  let out = system('ps ewww -p '.a:pid)
  if empty($STY) || stridx(out, 'STY='.$STY) < 0
    return 0
  endif
  let window = matchstr(out, 'WINDOW=\zs\d\+')
  if !empty(window)
    silent execute '!screen -X select '.window
    return !v:shell_error
  endif
endfunction

function! dispatch#screen#poll() abort
  if empty(s:waiting)
    return
  endif
  let request = s:waiting
  if !dispatch#pid(request)
    let s:waiting = {}
    call dispatch#complete(request)
  endif
endfunction

augroup dispatch_screen
  autocmd!
  autocmd VimResized * if !has('gui_running') | call dispatch#screen#poll() | endif
augroup END
